// SPDX-License-Identifier: MIT
/* Run via:
-- CSV:
MERKLE_INPUT_PATH=contracts/nft-redeemer/scripts/merkle_example.csv \
MERKLE_INPUT_FORMAT=csv \
forge script contracts/nft-redeemer/scripts/GenerateBeamMerkleProofs.s.sol:GenerateBeamMerkleProofs

-- JSON entries mode:
MERKLE_INPUT_PATH=contracts/nft-redeemer/scripts/merkle_example.json \
MERKLE_INPUT_FORMAT=json \
MERKLE_JSON_MODE=entries \
forge script contracts/nft-redeemer/scripts/GenerateBeamMerkleProofs.s.sol:GenerateBeamMerkleProofs

Optional:
MERKLE_OUTPUT_DIR=contracts/nft-redeemer/scripts/output

See merkle_example.csv and merkle_example.json for example input formats.
*/
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

contract GenerateBeamMerkleProofs is Script {
    struct Entry {
        address account;
        uint256 amount;
    }

    function run() external {
        string memory inputPath = vm.envString("MERKLE_INPUT_PATH");
        string memory format = vm.envOr("MERKLE_INPUT_FORMAT", string(""));
        string memory outputDir = _outputDir();

        Entry[] memory entries = _loadEntries(inputPath, format);
        require(entries.length > 0, "no entries");

        bytes32[] memory leaves = _buildLeaves(entries);
        bytes32[][] memory layers = _buildLayers(leaves);
        bytes32 root = layers[layers.length - 1][0];

        console2.log("Entries:", entries.length);
        console2.log("Merkle root:");
        console2.logBytes32(root);

        _maybeWriteRootFile(root);
        _maybeWriteSingleProof(entries, leaves, layers);
        _maybeWriteAllProofs(entries, layers, root, outputDir);
    }

    function _loadEntries(
        string memory inputPath,
        string memory format
    ) internal view returns (Entry[] memory entries) {
        bytes memory formatBytes = bytes(format);
        if (formatBytes.length == 0) {
            if (_endsWith(inputPath, ".csv")) {
                return _loadEntriesFromCsv(inputPath);
            }
            if (_endsWith(inputPath, ".json")) {
                return _loadEntriesFromJson(inputPath);
            }
            revert("unknown format; set MERKLE_INPUT_FORMAT");
        }

        if (_equalsIgnoreCase(format, "csv")) return _loadEntriesFromCsv(inputPath);
        if (_equalsIgnoreCase(format, "json")) return _loadEntriesFromJson(inputPath);
        revert("MERKLE_INPUT_FORMAT must be csv or json");
    }

    function _loadEntriesFromJson(
        string memory inputPath
    ) internal view returns (Entry[] memory entries) {
        // JSON mode "entries" (default):
        // {
        //   "entries": [
        //     {"address":"0x...","amount":"1000000000000000000"},
        //     ...
        //   ]
        // }
        // Use MERKLE_JSON_MODE=arrays for:
        // {"addresses": ["0x..."], "amounts": ["1000"]}
        string memory json = vm.readFile(inputPath);
        string memory jsonMode = vm.envOr("MERKLE_JSON_MODE", string("entries"));

        if (_equalsIgnoreCase(jsonMode, "entries")) {
            return _loadEntriesFromJsonEntriesMode(json);
        }
        if (_equalsIgnoreCase(jsonMode, "arrays")) {
            return _loadEntriesFromJsonArraysMode(json);
        }
        revert("MERKLE_JSON_MODE must be entries or arrays");
    }

    function _loadEntriesFromJsonEntriesMode(
        string memory json
    ) internal pure returns (Entry[] memory entries) {
        // Parser for object-array JSON like:
        // {"entries":[{"address":"0x...","amount":"123"}, ...]}
        bytes memory data = bytes(json);
        bytes memory addressKey = bytes('"address"');
        bytes memory amountKey = bytes('"amount"');

        uint256 count = _countOccurrences(data, addressKey);
        entries = new Entry[](count);

        uint256 cursor;
        for (uint256 i; i < count; ++i) {
            (entries[i], cursor) = _parseEntryAt(data, cursor, addressKey, amountKey);
        }
    }

    function _parseEntryAt(
        bytes memory data,
        uint256 cursor,
        bytes memory addressKey,
        bytes memory amountKey
    ) internal pure returns (Entry memory entry, uint256 nextCursor) {
        uint256 i = _indexOf(data, cursor, addressKey);
        require(i != type(uint256).max, "json address key not found");

        uint256 j = _valueStartAfterKey(data, i + addressKey.length);
        require(j < data.length && data[j] == '"', "json address must be string");

        uint256 k = _findNextByte(data, j + 1, '"');
        require(k != type(uint256).max, "json address quote not closed");
        entry.account = vm.parseAddress(string(_slice(data, j + 1, k)));

        i = _indexOf(data, k + 1, amountKey);
        require(i != type(uint256).max, "json amount key not found");
        j = _valueStartAfterKey(data, i + amountKey.length);
        require(j < data.length, "json amount missing");

        if (data[j] == '"') {
            k = _findNextByte(data, j + 1, '"');
            require(k != type(uint256).max, "json amount quote not closed");
            entry.amount = vm.parseUint(string(_slice(data, j + 1, k)));
            nextCursor = k + 1;
            return (entry, nextCursor);
        }

        k = j;
        while (k < data.length && !_isAmountTerminator(data[k])) {
            ++k;
        }
        entry.amount = vm.parseUint(string(_trim(_slice(data, j, k))));
        nextCursor = k;
    }

    function _loadEntriesFromJsonArraysMode(
        string memory json
    ) internal view returns (Entry[] memory entries) {
        string memory addressesKey = vm.envOr("MERKLE_JSON_ADDRESSES_KEY", string(".addresses"));
        string memory amountsKey = vm.envOr("MERKLE_JSON_AMOUNTS_KEY", string(".amounts"));

        address[] memory addresses = vm.parseJsonAddressArray(json, addressesKey);
        bytes memory rawAmounts = vm.parseJson(json, amountsKey);

        bool amountsAreStrings = vm.envOr("MERKLE_JSON_AMOUNTS_ARE_STRINGS", true);
        uint256[] memory amounts;
        if (amountsAreStrings) {
            string[] memory amountStrings = abi.decode(rawAmounts, (string[]));
            require(amountStrings.length == addresses.length, "json length mismatch");
            amounts = new uint256[](amountStrings.length);
            for (uint256 i; i < amountStrings.length; ++i) {
                amounts[i] = vm.parseUint(amountStrings[i]);
            }
        } else {
            amounts = abi.decode(rawAmounts, (uint256[]));
            require(amounts.length == addresses.length, "json length mismatch");
        }

        entries = new Entry[](addresses.length);
        for (uint256 i; i < addresses.length; ++i) {
            entries[i] = Entry({account: addresses[i], amount: amounts[i]});
        }
    }

    function _loadEntriesFromCsv(
        string memory inputPath
    ) internal view returns (Entry[] memory entries) {
        string memory csv = vm.readFile(inputPath);
        bytes memory data = bytes(csv);

        uint256 count = _countCsvEntries(data);
        entries = new Entry[](count);

        uint256 start;
        uint256 entryIndex;
        bool headerHandled;

        while (start < data.length) {
            (uint256 end, uint256 nextStart) = _findLine(data, start);
            bytes memory line = _slice(data, start, end);
            line = _trim(line);
            start = nextStart;

            if (line.length == 0) continue;

            (bytes memory left, bytes memory right) = _splitOnce(line, ",");
            left = _trim(left);
            right = _trim(right);

            if (!headerHandled && _equalsIgnoreCaseBytes(left, bytes("address"))) {
                headerHandled = true;
                continue;
            }
            headerHandled = true;

            entries[entryIndex] = Entry({
                account: vm.parseAddress(string(left)), amount: vm.parseUint(string(right))
            });
            ++entryIndex;
        }

        require(entryIndex == count, "csv parsed count mismatch");
    }

    function _countCsvEntries(
        bytes memory data
    ) internal pure returns (uint256 count) {
        uint256 start;
        bool headerHandled;

        while (start < data.length) {
            (uint256 end, uint256 nextStart) = _findLine(data, start);
            bytes memory line = _trim(_slice(data, start, end));
            start = nextStart;

            if (line.length == 0) continue;

            bytes memory firstCol;
            bytes memory unused;
            (firstCol, unused) = _splitOnce(line, ",");
            firstCol = _trim(firstCol);

            if (!headerHandled && _equalsIgnoreCaseBytes(firstCol, bytes("address"))) {
                headerHandled = true;
                continue;
            }
            headerHandled = true;
            ++count;
        }
    }

    function _buildLeaves(
        Entry[] memory entries
    ) internal pure returns (bytes32[] memory leaves) {
        leaves = new bytes32[](entries.length);
        for (uint256 i; i < entries.length; ++i) {
            leaves[i] = _leaf(entries[i].account, entries[i].amount);
        }
    }

    function _buildLayers(
        bytes32[] memory leaves
    ) internal pure returns (bytes32[][] memory layers) {
        uint256 depth = 1;
        uint256 width = leaves.length;
        while (width > 1) {
            width = (width + 1) / 2;
            ++depth;
        }

        layers = new bytes32[][](depth);
        layers[0] = leaves;

        for (uint256 d = 1; d < depth; ++d) {
            bytes32[] memory prev = layers[d - 1];
            uint256 currLen = (prev.length + 1) / 2;
            bytes32[] memory curr = new bytes32[](currLen);

            uint256 out;
            for (uint256 i; i < prev.length; i += 2) {
                if (i + 1 == prev.length) {
                    curr[out] = prev[i];
                } else {
                    curr[out] = _hashPair(prev[i], prev[i + 1]);
                }
                ++out;
            }

            layers[d] = curr;
        }
    }

    function _proofAt(
        bytes32[][] memory layers,
        uint256 leafIndex
    ) internal pure returns (bytes32[] memory proof) {
        if (layers.length == 1) return new bytes32[](0);

        bytes32[] memory tmp = new bytes32[](layers.length - 1);
        uint256 p;
        uint256 index = leafIndex;

        for (uint256 d; d < layers.length - 1; ++d) {
            bytes32[] memory level = layers[d];
            uint256 siblingIndex = index ^ 1;
            if (siblingIndex < level.length) {
                tmp[p] = level[siblingIndex];
                ++p;
            }
            index /= 2;
        }

        proof = new bytes32[](p);
        for (uint256 i; i < p; ++i) {
            proof[i] = tmp[i];
        }
    }

    function _maybeWriteRootFile(
        bytes32 root
    ) internal {
        string memory rootPath = vm.envOr("MERKLE_ROOT_OUTPUT_PATH", string(""));
        if (bytes(rootPath).length == 0) return;

        vm.writeFile(rootPath, vm.toString(root));
        console2.log("Wrote root to:", rootPath);
    }

    function _maybeWriteSingleProof(
        Entry[] memory entries,
        bytes32[] memory leaves,
        bytes32[][] memory layers
    ) internal {
        string memory targetAccountRaw = vm.envOr("MERKLE_TARGET_ACCOUNT", string(""));
        string memory targetAmountRaw = vm.envOr("MERKLE_TARGET_AMOUNT", string(""));
        if (bytes(targetAccountRaw).length == 0 || bytes(targetAmountRaw).length == 0) return;

        address targetAccount = vm.parseAddress(targetAccountRaw);
        uint256 targetAmount = vm.parseUint(targetAmountRaw);

        bool found;
        uint256 foundIndex;
        for (uint256 i; i < entries.length; ++i) {
            if (entries[i].account == targetAccount && entries[i].amount == targetAmount) {
                found = true;
                foundIndex = i;
                break;
            }
        }
        require(found, "target entry not found");

        bytes32[] memory proof = _proofAt(layers, foundIndex);
        console2.log("Target index:", foundIndex);
        console2.log("Target leaf:");
        console2.logBytes32(leaves[foundIndex]);
        console2.log("Proof length:", proof.length);
        for (uint256 i; i < proof.length; ++i) {
            console2.logBytes32(proof[i]);
        }

        string memory proofPath = vm.envOr("MERKLE_SINGLE_PROOF_OUTPUT_PATH", string(""));
        if (bytes(proofPath).length != 0) {
            vm.writeFile(
                proofPath,
                _formatSingleProofJson(targetAccount, targetAmount, leaves[foundIndex], proof)
            );
            console2.log("Wrote single proof to:", proofPath);
        }
    }

    function _maybeWriteAllProofs(
        Entry[] memory entries,
        bytes32[][] memory layers,
        bytes32 root,
        string memory outputDir
    ) internal {
        _ensureDir(outputDir);
        string memory proofsPath = _joinPath(outputDir, "proofs.json");

        vm.writeFile(
            proofsPath, string.concat('{"merkleRoot":"', vm.toString(root), '","claims":{')
        );
        for (uint256 i; i < entries.length; ++i) {
            bytes32[] memory proof = _proofAt(layers, i);
            vm.writeLine(proofsPath, _claimsIndexLine(entries[i], proof, i + 1 != entries.length));
            _writeClaimProofFile(outputDir, entries[i], proof);
        }
        vm.writeLine(proofsPath, "}}");

        console2.log("Wrote all proofs JSON to:", proofsPath);
        console2.log("Wrote per-claim JSON files to:", outputDir);
    }

    function _claimsIndexLine(
        Entry memory entry,
        bytes32[] memory proof,
        bool withComma
    ) internal pure returns (string memory) {
        string memory line = string.concat(
            '"',
            vm.toString(entry.account),
            '":{"amount":"',
            vm.toString(entry.amount),
            '","proof":',
            _proofArrayToJson(proof),
            "}"
        );

        if (withComma) {
            return string.concat(line, ",");
        }
        return line;
    }

    function _writeClaimProofFile(
        string memory outputDir,
        Entry memory entry,
        bytes32[] memory proof
    ) internal {
        string memory claimFileName =
            string.concat(_toLowerString(vm.toString(entry.account)), ".json");
        string memory claimPath = _joinPath(outputDir, claimFileName);
        vm.writeFile(claimPath, _formatClaimProofJson(entry.account, entry.amount, proof));
    }

    function _outputDir() internal view returns (string memory) {
        return vm.envOr("MERKLE_OUTPUT_DIR", string("contracts/nft-redeemer/scripts/output"));
    }

    function _ensureDir(
        string memory path
    ) internal {
        vm.createDir(path, true);
    }

    function _joinPath(
        string memory base,
        string memory name
    ) internal pure returns (string memory) {
        bytes memory b = bytes(base);
        if (b.length > 0 && b[b.length - 1] == "/") {
            return string.concat(base, name);
        }
        return string.concat(base, "/", name);
    }

    function _leaf(
        address account,
        uint256 amount
    ) internal pure returns (bytes32) {
        bytes32 first = keccak256(abi.encodePacked(account, amount));
        return keccak256(bytes.concat(first));
    }

    function _hashPair(
        bytes32 a,
        bytes32 b
    ) internal pure returns (bytes32) {
        return a < b ? keccak256(bytes.concat(a, b)) : keccak256(bytes.concat(b, a));
    }

    function _formatSingleProofJson(
        address account,
        uint256 amount,
        bytes32 leaf,
        bytes32[] memory proof
    ) internal pure returns (string memory) {
        string memory json = string.concat(
            '{"account":"',
            vm.toString(account),
            '","amount":"',
            vm.toString(amount),
            '","leaf":"',
            vm.toString(leaf),
            '","proof":['
        );

        for (uint256 i; i < proof.length; ++i) {
            if (i > 0) json = string.concat(json, ",");
            json = string.concat(json, '"', vm.toString(proof[i]), '"');
        }

        return string.concat(json, "]}");
    }

    function _formatClaimProofJson(
        address account,
        uint256 amount,
        bytes32[] memory proof
    ) internal pure returns (string memory) {
        string memory json = string.concat(
            '{"account":"', vm.toString(account), '","amount":"', vm.toString(amount), '","proof":['
        );

        for (uint256 i; i < proof.length; ++i) {
            if (i > 0) json = string.concat(json, ",");
            json = string.concat(json, '"', vm.toString(proof[i]), '"');
        }

        return string.concat(json, "]}");
    }

    function _proofArrayToJson(
        bytes32[] memory proof
    ) internal pure returns (string memory out) {
        out = "[";
        for (uint256 i; i < proof.length; ++i) {
            if (i > 0) {
                out = string.concat(out, ",");
            }
            out = string.concat(out, '"', vm.toString(proof[i]), '"');
        }
        out = string.concat(out, "]");
    }

    function _findLine(
        bytes memory data,
        uint256 start
    ) internal pure returns (uint256 end, uint256 nextStart) {
        uint256 i = start;
        while (i < data.length && data[i] != 0x0a) {
            ++i;
        }
        end = i;
        nextStart = i < data.length ? i + 1 : i;
    }

    function _countOccurrences(
        bytes memory data,
        bytes memory needle
    ) internal pure returns (uint256 count) {
        uint256 cursor;
        while (true) {
            uint256 idx = _indexOf(data, cursor, needle);
            if (idx == type(uint256).max) break;
            ++count;
            cursor = idx + needle.length;
        }
    }

    function _indexOf(
        bytes memory data,
        uint256 start,
        bytes memory needle
    ) internal pure returns (uint256) {
        if (needle.length == 0 || data.length < needle.length || start >= data.length) {
            return type(uint256).max;
        }

        uint256 last = data.length - needle.length;
        for (uint256 i = start; i <= last; ++i) {
            bool ok = true;
            for (uint256 j; j < needle.length; ++j) {
                if (data[i + j] != needle[j]) {
                    ok = false;
                    break;
                }
            }
            if (ok) return i;
        }
        return type(uint256).max;
    }

    function _valueStartAfterKey(
        bytes memory data,
        uint256 start
    ) internal pure returns (uint256) {
        uint256 i = start;
        while (i < data.length && data[i] != ":") {
            ++i;
        }
        require(i < data.length, "json key missing colon");
        ++i;
        while (i < data.length && _isWhitespace(data[i])) {
            ++i;
        }
        return i;
    }

    function _findNextByte(
        bytes memory data,
        uint256 start,
        bytes1 target
    ) internal pure returns (uint256) {
        for (uint256 i = start; i < data.length; ++i) {
            if (data[i] == target) return i;
        }
        return type(uint256).max;
    }

    function _isAmountTerminator(
        bytes1 c
    ) internal pure returns (bool) {
        return c == "," || c == "}" || c == "]" || _isWhitespace(c);
    }

    function _splitOnce(
        bytes memory src,
        bytes1 delim
    ) internal pure returns (bytes memory left, bytes memory right) {
        for (uint256 i; i < src.length; ++i) {
            if (src[i] == delim) {
                left = _slice(src, 0, i);
                right = _slice(src, i + 1, src.length);
                return (left, right);
            }
        }
        revert("delimiter not found");
    }

    function _slice(
        bytes memory data,
        uint256 start,
        uint256 end
    ) internal pure returns (bytes memory out) {
        require(end >= start && end <= data.length, "invalid slice");
        out = new bytes(end - start);
        for (uint256 i; i < out.length; ++i) {
            out[i] = data[start + i];
        }
    }

    function _trim(
        bytes memory src
    ) internal pure returns (bytes memory out) {
        if (src.length == 0) return src;

        uint256 s;
        uint256 e = src.length;

        while (s < e && _isWhitespace(src[s])) {
            ++s;
        }
        while (e > s && _isWhitespace(src[e - 1])) {
            --e;
        }

        return _slice(src, s, e);
    }

    function _isWhitespace(
        bytes1 c
    ) internal pure returns (bool) {
        return c == 0x20 || c == 0x09 || c == 0x0d || c == 0x0a;
    }

    function _endsWith(
        string memory s,
        string memory suffix
    ) internal pure returns (bool) {
        bytes memory a = bytes(s);
        bytes memory b = bytes(suffix);
        if (b.length > a.length) return false;
        uint256 offset = a.length - b.length;
        for (uint256 i; i < b.length; ++i) {
            if (a[offset + i] != b[i]) return false;
        }
        return true;
    }

    function _equalsIgnoreCase(
        string memory a,
        string memory b
    ) internal pure returns (bool) {
        return _equalsIgnoreCaseBytes(bytes(a), bytes(b));
    }

    function _equalsIgnoreCaseBytes(
        bytes memory a,
        bytes memory b
    ) internal pure returns (bool) {
        if (a.length != b.length) return false;
        for (uint256 i; i < a.length; ++i) {
            if (_toLower(a[i]) != _toLower(b[i])) return false;
        }
        return true;
    }

    function _toLower(
        bytes1 c
    ) internal pure returns (bytes1) {
        if (c >= 0x41 && c <= 0x5A) return bytes1(uint8(c) + 32);
        return c;
    }

    function _toLowerString(
        string memory s
    ) internal pure returns (string memory) {
        bytes memory bs = bytes(s);
        for (uint256 i; i < bs.length; ++i) {
            bs[i] = _toLower(bs[i]);
        }
        return string(bs);
    }
}
