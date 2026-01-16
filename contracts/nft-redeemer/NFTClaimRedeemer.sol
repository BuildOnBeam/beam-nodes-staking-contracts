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

    mapping(address => uint256) public claims;

    event RedeemedUnclaimed(address indexed user, uint256 amount);

    constructor(
        address _nft,
        uint256 _baseRedemptionAmount,
        uint256 _alternateRedemptionAmount,
        address _initialOwner,
        address _burner
    )
        NFTRedeemer(_nft, _baseRedemptionAmount, _alternateRedemptionAmount, _initialOwner, _burner)
    {}

    function setClaim(
        address account,
        uint256 value
    ) external onlyOwner {
        claims[account] = value;
    }

    function setClaimBatch(
        address[] calldata accounts,
        uint256[] calldata values
    ) external onlyOwner {
        uint256 len = accounts.length;
        if (len != values.length) {
            revert InputMismatch();
        }

        for (uint256 i = 0; i < len; i++) {
            claims[accounts[i]] = values[i];
        }
    }

    function redeemUnclaimed(
        address recipient
    ) external virtual nonReentrant whenNotPaused {
        _redeemUnclaimed(recipient);
    }

    function _redeemUnclaimed(
        address recipient
    ) internal virtual {
        address sender = _msgSender();
        uint256 payout = claims[sender];

        if (payout == 0) {
            revert NoClaimableTokens(sender);
        }

        if (address(this).balance < payout) {
            revert InsufficientContractBalance(payout, address(this).balance);
        }

        claims[sender] = 0;

        payable(recipient).sendValue(payout);

        emit RedeemedUnclaimed(sender, payout);
    }
}
