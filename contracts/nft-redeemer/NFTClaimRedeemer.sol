// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {NFTRedeemer, Address} from "./NFTRedeemer.sol";

/**
 * @title NFT Claim Redeemer
 * @dev This contract allows users to redeem NFTs by claiming them through a specified redeemer contract.
 * It extends the NFTRedeemer contract to provide functionality to redeem unclaimed tokens by address.
 */
contract NFTClaimRedeemer is NFTRedeemer {
    using Address for address payable;

    error InputMismatch();
    error NoClaimableTokens(address beneficiary);

    mapping(address => uint256) internal _claims;

    event RedeemedUnclaimed(address indexed user, address indexed recipient, uint256 amount);

    constructor(
        address _nft,
        uint256 _baseRedemptionAmount,
        uint256 _alternateRedemptionAmount,
        address _initialOwner,
        address _burner
    )
        NFTRedeemer(_nft, _baseRedemptionAmount, _alternateRedemptionAmount, _initialOwner, _burner)
    {}

    /**
     * @notice Sets the claimable amount for a specific account. Owner only.
     * @param account The address of the account.
     * @param value The amount of claimable tokens.
     */
    function setClaim(
        address account,
        uint256 value
    ) external onlyOwner {
        _claims[account] = value;
    }

    /**
     * @notice Sets the claimable amounts for multiple accounts in a batch. Owner only.
     * @param accounts An array of account addresses.
     * @param values An array of claimable amounts corresponding to each account.
     *
     * The length of the accounts and values arrays must be the same.
     */
    function setClaimBatch(
        address[] calldata accounts,
        uint256[] calldata values
    ) external onlyOwner {
        uint256 len = accounts.length;
        if (len != values.length) {
            revert InputMismatch();
        }

        for (uint256 i = 0; i < len; i++) {
            _claims[accounts[i]] = values[i];
        }
    }

    /**
     * @notice Redeems unclaimed tokens for the sender and sends the payout to the specified recipient.
     * @param recipient The address to receive the payout for the redeemed claim.
     *
     * The sender must have a claimable amount greater than zero, and the contract must have
     * sufficient balance to cover the payout.
     */
    function redeemUnclaimed(
        address recipient
    ) external virtual nonReentrant whenNotPaused {
        _redeemUnclaimed(_msgSender(), recipient);
    }

    /**
     * @notice Returns the claimable amount for a specific account.
     * @param account The address of the account.
     * @return The amount of claimable tokens for the account.
     */
    function getUnclaimedAmount(
        address account
    ) public view virtual returns (uint256) {
        return _claims[account];
    }

    /**
     * @notice Internal function to handle the redemption of unclaimed tokens. It checks the claimable amount for the sender,
     * ensures the contract has sufficient balance, resets the claim to zero, and sends the payout to the recipient.
     * @param claimer The address of the account claiming the tokens.
     * @param recipient The address to receive the payout for the redeemed claim.
     *
     * The sender must have a claimable amount greater than zero, and the contract must have
     * sufficient balance to cover the payout.
     */
    function _redeemUnclaimed(
        address claimer,
        address recipient
    ) internal virtual {
        uint256 payout = _claims[claimer];

        if (payout == 0) {
            revert NoClaimableTokens(claimer);
        }

        if (address(this).balance < payout) {
            revert InsufficientContractBalance(payout, address(this).balance);
        }

        _claims[claimer] = 0;

        payable(recipient).sendValue(payout);

        emit RedeemedUnclaimed(claimer, recipient, payout);
    }
}
