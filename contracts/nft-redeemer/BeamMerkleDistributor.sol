// SPDX-License-Identifier: GPL-3.0-or-later
// adapted from: https://github.com/Uniswap/merkle-distributor
pragma solidity ^0.8.20;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IBeamMerkleDistributor} from "./interfaces/IBeamMerkleDistributor.sol";

contract BeamMerkleDistributor is
    IBeamMerkleDistributor,
    Ownable,
    Pausable,
    ReentrancyGuard,
    ERC165
{
    using SafeERC20 for IERC20;
    using Address for address payable;

    address public immutable override token;
    bytes32 public override merkleRoot;
    uint256 public endTime;

    mapping(address => bool) public override isClaimed;

    constructor(
        address token_,
        bytes32 merkleRoot_,
        uint256 endTime_,
        address owner_
    ) Ownable(owner_) {
        token = token_;
        merkleRoot = merkleRoot_;
        endTime = endTime_;

        _pause(); // Start in paused state
    }

    function setMerkleRoot(
        bytes32 merkleRoot_
    ) external virtual onlyOwner nonReentrant {
        merkleRoot = merkleRoot_;
    }

    function setEndTime(
        uint256 endTime_
    ) external virtual onlyOwner {
        endTime = endTime_;
    }

    function pause() external virtual onlyOwner {
        _pause();
    }

    function unpause() external virtual onlyOwner {
        _unpause();
    }

    function withdraw(
        address token_
    ) external virtual override onlyOwner nonReentrant {
        bool isNative = token_ == address(0);
        // Check contract balance of the specified token
        uint256 balance;
        if (isNative) {
            balance = address(this).balance;
        } else {
            balance = IERC20(token_).balanceOf(address(this));
        }
        if (balance == 0) revert NoBalanceToWithdraw();

        // Transfer the entire balance of the specified token to the owner
        address ownerAddress = owner();
        if (isNative) {
            payable(ownerAddress).sendValue(balance);
        } else {
            IERC20(token_).safeTransfer(ownerAddress, balance);
        }

        emit Withdrawn(token_, balance, ownerAddress);
    }

    function claim(
        address account,
        uint256 amount,
        bytes32[] calldata proof
    ) external virtual override whenNotPaused nonReentrant {
        if (block.timestamp > endTime) revert ClaimWindowFinished();
        if (isClaimed[account]) revert AlreadyClaimed();

        // Verify the merkle proof.
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encodePacked(account, amount))));
        if (!MerkleProof.verify(proof, merkleRoot, leaf)) revert InvalidProof();

        // Mark it claimed and send the token.
        isClaimed[account] = true;
        IERC20(token).safeTransfer(account, amount);

        emit Claimed(account, amount);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override returns (bool) {
        return interfaceId == type(IBeamMerkleDistributor).interfaceId
            || super.supportsInterface(interfaceId);
    }
}
