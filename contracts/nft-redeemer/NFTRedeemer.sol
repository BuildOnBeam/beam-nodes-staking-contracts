// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

/**
 * @title NFTRedeemer
 * @notice Allows users to redeem ERC721 tokens for native ETH. Redeemed NFTs are sent to a specified
 *         burn address, to support tokens without burnable functionality.
 *         Certain token IDs can receive an alternate redemption amount using an on-chain bitmap.
 */
contract NFTRedeemer is Ownable, Pausable, ReentrancyGuard, ERC165 {
    using SafeERC20 for IERC20;
    using Address for address payable;

    // ------------------------------------------------------------------------
    // Errors
    // ------------------------------------------------------------------------

    /**
     * @notice Thrown when the caller is not the owner of a specified token.
     * @param tokenId The token ID the caller attempted to redeem.
     */
    error NotTokenOwner(uint256 tokenId);

    /**
     * @notice Thrown when contract balance is insufficient for a redemption or withdrawal.
     * @param requested The amount requested.
     * @param available The contract's current balance.
     */
    error InsufficientContractBalance(uint256 requested, uint256 available);

    /**
     * @notice Thrown when a zero address is supplied where not allowed.
     */
    error ZeroAddress();

    /**
     * @notice Thrown when a batch request is empty.
     */
    error EmptyTokenIds();

    // ------------------------------------------------------------------------
    // State variables
    // ------------------------------------------------------------------------

    /**
     * @notice The ERC721 contract whose tokens can be redeemed.
     */
    IERC721 public immutable nft;

    /**
     * @notice Standard redemption amount (in wei) for all NFTs.
     */
    uint256 public baseRedemptionAmount;

    /**
     * @notice Alternate redemption amount (in wei) for specific NFTs.
     */
    uint256 public alternateRedemptionAmount;

    /**
     * @notice Address where redeemed NFTs are sent (burned).
     */
    address public burner;

    /**
     * @notice Bitmap storing alternatively priced token IDs.
     * @dev Each uint256 can store alternate pricing flags for 256 token IDs.
     *      slot = tokenId >> 8, bit = tokenId & 0xFF
     */
    mapping(uint256 => uint256) internal _alternatePriceBitmap;

    // ------------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------------

    /**
     * @notice Emitted when a single NFT is redeemed.
     * @param user The user who redeemed the NFT.
     * @param tokenId Token ID redeemed.
     * @param amount ETH paid out.
     */
    event Redeemed(address indexed user, uint256 indexed tokenId, uint256 amount);

    /**
     * @notice Emitted when the redemption amount changes.
     * @param newAmount The updated amount.
     * @param alternate True if the updated amount is the alternate amount.
     */
    event RedemptionAmountSet(uint256 newAmount, bool indexed alternate);

    /**
     * @notice Emitted when the contract owner withdraws ETH.
     * @param owner The address receiving ETH.
     * @param amount Amount transferred.
     */
    event Withdrawn(address indexed owner, uint256 amount);

    /**
     * @notice Emitted when ERC20 tokens are recovered.
     * @param token The ERC20 token address.
     * @param amount Amount of tokens recovered.
     * @param recipient Address receiving the recovered tokens.
     */
    event RecoveredERC20(address indexed token, uint256 amount, address indexed recipient);

    /**
     * @notice Emitted when ERC721 tokens are recovered.
     * @param token The ERC721 token address.
     * @param tokenId The token ID recovered.
     * @param recipient Address receiving the recovered token.
     */
    event RecoveredERC721(address indexed token, uint256 tokenId, address indexed recipient);

    // ------------------------------------------------------------------------
    // Constructor & Co.
    // ------------------------------------------------------------------------

    /**
     * @notice Creates the NFT redeemer contract.
     * @param _nft Address of the ERC721 contract.
     * @param _baseRedemptionAmount Normal redemption payout.
     * @param _alternateRedemptionAmount Alternate redemption payout for flagged tokens.
     * @param _initialOwner Initial owner of the contract.
     * @param _burner Address where redeemed NFTs are sent (burned).
     */
    constructor(
        address _nft,
        uint256 _baseRedemptionAmount,
        uint256 _alternateRedemptionAmount,
        address _initialOwner,
        address _burner
    ) Ownable(_initialOwner) {
        if (_nft == address(0) || _burner == address(0) || _initialOwner == address(0)) {
            revert ZeroAddress();
        }

        nft = IERC721(_nft);

        baseRedemptionAmount = _baseRedemptionAmount;
        alternateRedemptionAmount = _alternateRedemptionAmount;
        emit RedemptionAmountSet(_baseRedemptionAmount, false);
        emit RedemptionAmountSet(_alternateRedemptionAmount, true);

        burner = _burner;
    }

    /// @notice Allows the contract to receive ETH.
    receive() external payable virtual {}

    // ------------------------------------------------------------------------
    // Redeem logic
    // ------------------------------------------------------------------------

    /**
     * @notice Redeems a single NFT in exchange for ETH. The NFT is burned.
     * @dev Requires caller to own the NFT.
     * @param tokenId The token ID being redeemed.
     * @param recipient The address receiving the redemption amount.
     */
    function redeem(
        uint256 tokenId,
        address recipient
    ) external virtual whenNotPaused nonReentrant {
        address sender = msg.sender;
        if (nft.ownerOf(tokenId) != sender) revert NotTokenOwner(tokenId);

        uint256 payout =
            isTokenAlternate(tokenId) ? alternateRedemptionAmount : baseRedemptionAmount;

        if (address(this).balance < payout) {
            revert InsufficientContractBalance(payout, address(this).balance);
        }

        nft.transferFrom(sender, burner, tokenId);

        payable(recipient).sendValue(payout);

        emit Redeemed(sender, tokenId, payout);
    }

    /**
     * @notice Redeems multiple NFTs in a single transaction. All NFTs are burned.
     * @dev Reverts if caller is not owner of any provided token.
     * @param tokenIds An array of token IDs to redeem.
     * @param recipient The address receiving the redemption amount.
     */
    function redeemBatch(
        uint256[] calldata tokenIds,
        address recipient
    ) external virtual whenNotPaused nonReentrant {
        uint256 len = tokenIds.length;
        if (len == 0) revert EmptyTokenIds();

        address sender = msg.sender;
        uint256 totalPayout;

        for (uint256 i = 0; i < len; i++) {
            uint256 tokenId = tokenIds[i];

            if (nft.ownerOf(tokenId) != sender) {
                revert NotTokenOwner(tokenId);
            }

            uint256 payout =
                isTokenAlternate(tokenId) ? alternateRedemptionAmount : baseRedemptionAmount;

            totalPayout += payout;

            nft.transferFrom(sender, burner, tokenId);

            emit Redeemed(sender, tokenId, payout);
        }

        if (address(this).balance < totalPayout) {
            revert InsufficientContractBalance(totalPayout, address(this).balance);
        }

        payable(recipient).sendValue(totalPayout);
    }

    /**
     * @notice Gets the redemption amount for a specific token ID.
     * @param tokenId The token ID to check.
     * @return The redemption amount (in wei).
     */
    function getRedemptionAmount(
        uint256 tokenId
    ) public view virtual returns (uint256) {
        return isTokenAlternate(tokenId) ? alternateRedemptionAmount : baseRedemptionAmount;
    }

    /**
     * @notice Returns whether a token ID is alternatively priced.
     * @dev Reads from the alternate-pricing bitmap.
     * @param tokenId The token ID to check.
     * @return True if alternate, false otherwise.
     */
    function isTokenAlternate(
        uint256 tokenId
    ) public view virtual returns (bool) {
        (uint256 slot, uint256 bit) = _bitmapLocation(tokenId);
        return (_alternatePriceBitmap[slot] >> bit) & 1 == 1;
    }

    // ------------------------------------------------------------------------
    // Owner functions
    // ------------------------------------------------------------------------

    /**
     * @notice Updates the alternate redemption amount.
     * @param amount New alternate payout amount (in wei).
     */
    function setAlternateRedemptionAmount(
        uint256 amount
    ) external virtual onlyOwner {
        alternateRedemptionAmount = amount;
        emit RedemptionAmountSet(amount, true);
    }

    /**
     * @notice Updates the normal redemption amount.
     * @param amount New normal payout amount (in wei).
     */
    function setBaseRedemptionAmount(
        uint256 amount
    ) external virtual onlyOwner {
        baseRedemptionAmount = amount;
        emit RedemptionAmountSet(amount, false);
    }

    /**
     * @notice Updates the burner address (NFTs are sent there upon redemption).
     * @param _burner New burner address.
     */
    function setBurner(
        address _burner
    ) external virtual onlyOwner {
        if (_burner == address(0)) {
            revert ZeroAddress();
        }
        burner = _burner;
    }

    /**
     * @notice Marks a token ID as alternate or not alternatively priced.
     * @dev Uses a bitmap for gas-efficiency.
     * @param tokenId Token ID to update.
     * @param value True to enable alternate, false to disable.
     */
    function setTokenAlternate(
        uint256 tokenId,
        bool value
    ) external virtual onlyOwner {
        (uint256 slot, uint256 bit) = _bitmapLocation(tokenId);

        if (value) {
            _alternatePriceBitmap[slot] |= (1 << bit);
        } else {
            _alternatePriceBitmap[slot] &= ~(1 << bit);
        }
    }

    /**
     * @notice Sets alternate status for multiple token IDs with minimal gas.
     * @dev Groups token IDs by bitmap slot so each slot is updated only once.
     *      This is significantly cheaper than updating the bitmap per iteration.
     *
     * @param tokenIds Array of token IDs to update.
     * @param value True = enable alternate, False = disable alternate.
     */
    function setTokenAlternateBatch(
        uint256[] calldata tokenIds,
        bool value
    ) external virtual onlyOwner {
        uint256 len = tokenIds.length;
        if (len == 0) revert EmptyTokenIds();

        // We create a mapping using two dynamic arrays:
        //   1. slotIndices[] – list of distinct slot numbers encountered
        //   2. slotMasks[]   – accumulated bitmasks for those slots
        //
        // Worst case: all tokenIds belong to different slots (1:1 mapping).
        uint256[] memory slots = new uint256[](len);
        uint256[] memory masks = new uint256[](len);
        uint256 slotCount = 0;

        // GROUP BY SLOT (accumulate masks in memory)
        for (uint256 i = 0; i < len; i++) {
            uint256 tokenId = tokenIds[i];

            (uint256 slot, uint256 bit) = _bitmapLocation(tokenId);
            uint256 bitMask = (1 << bit);

            // Check if we have already encountered this slot
            bool found = false;
            for (uint256 j = 0; j < slotCount; j++) {
                if (slots[j] == slot) {
                    masks[j] |= bitMask;
                    found = true;
                    break;
                }
            }

            // New slot
            if (!found) {
                slots[slotCount] = slot;
                masks[slotCount] = bitMask;
                slotCount++;
            }
        }

        // APPLY SLOT UPDATES TO STORAGE (one SSTORE per slot)
        if (value) {
            // Set bits
            for (uint256 i = 0; i < slotCount; i++) {
                _alternatePriceBitmap[slots[i]] |= masks[i];
            }
        } else {
            // Clear bits
            for (uint256 i = 0; i < slotCount; i++) {
                _alternatePriceBitmap[slots[i]] &= ~masks[i];
            }
        }
    }

    /**
     * @notice Withdraws ETH from the contract.
     * @param amount Amount to withdraw (in wei).
     */
    function withdraw(
        uint256 amount
    ) external virtual onlyOwner {
        if (address(this).balance < amount) {
            revert InsufficientContractBalance(amount, address(this).balance);
        }

        payable(msg.sender).sendValue(amount);

        emit Withdrawn(msg.sender, amount);
    }

    /**
     * @notice Recovers ERC20 tokens sent to the contract by mistake.
     * @param token Address of the ERC20 token.
     * @param amount Amount of tokens to recover.
     * @param recipient Address to receive the recovered tokens.
     */
    function recoverERC20(
        address token,
        uint256 amount,
        address recipient
    ) external virtual onlyOwner {
        IERC20(token).safeTransfer(recipient, amount);
        emit RecoveredERC20(token, amount, recipient);
    }

    /**
     * @notice Recovers ERC721 tokens sent to the contract by mistake.
     * @param token Address of the ERC721 token.
     * @param tokenIds Array of token IDs to recover.
     */
    function recoverERC721(
        address token,
        uint256[] memory tokenIds,
        address recipient
    ) external virtual onlyOwner {
        IERC721 erc721 = IERC721(token);
        address from = address(this);

        for (uint256 i = 0; i < tokenIds.length; i++) {
            erc721.transferFrom(from, recipient, tokenIds[i]);
            emit RecoveredERC721(token, tokenIds[i], recipient);
        }
    }

    /**
     * @notice Pauses the redeeming functionality.
     * @dev Owner only.
     */
    function pause() external virtual onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses the redeeming functionality.
     * @dev Owner only.
     */
    function unpause() external virtual onlyOwner {
        _unpause();
    }

    // ------------------------------------------------------------------------
    // Internal helpers
    // ------------------------------------------------------------------------

    /**
     * @notice Computes the bitmap slot and bit index for a token ID.
     * @param tokenId Token ID.
     * @return slot Storage slot index.
     * @return bit Bit position within the slot.
     */
    function _bitmapLocation(
        uint256 tokenId
    ) internal pure virtual returns (uint256 slot, uint256 bit) {
        slot = tokenId >> 8; // tokenId / 256
        bit = tokenId & 0xFF; // tokenId % 256
    }
}
