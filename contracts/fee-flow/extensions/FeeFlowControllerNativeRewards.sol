// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.25;

import {FeeFlowControllerNative, SafeTransferLib, WETH} from "../FeeFlowControllerNative.sol";

/// @dev Minimal interface for Beam "Native721TokenStakingManager" contract.
interface IStakingManagerMinimal {
    function registerProtocolRewards(
        address token,
        uint256 amount
    ) external;
}

/// @title FeeFlowControllerNative - Beam PoS rewards extension
/// @author xtools-at @ Beam Labs
/// @notice Uses funds collected in native currency to set up WETH rewards for Beam PoS.
contract FeeFlowControllerNativeRewards is FeeFlowControllerNative {
    using SafeTransferLib for WETH;

    uint256 public immutable incentiveBps; // 1 == 0.01%; 10_000 == 100%
    uint256 public immutable minNativeBalanceForRegister; // 1e18 == 1 ETH

    error NativeBalanceTooLow(uint256 currentBalance);
    error InvalidConfiguration(uint256 value);

    /// @dev Initializes the FeeFlowControllerNative contract, and sets up rewards configuration.
    /// @notice See {FeeFlowControllerNative-constructor}.
    /// @param incentiveBps_ The incentive in basis points for callers triggering reward registration (1-10_000 => 0.01%-100%).
    /// @param minNativeBalanceForRegister_ The minimum native token balance required to register rewards.
    constructor(
        uint256 initPrice,
        address wethAddress,
        address paymentReceiver_,
        uint256 epochPeriod_,
        uint256 priceMultiplier_,
        uint256 minInitPrice_,
        uint256 incentiveBps_,
        uint256 minNativeBalanceForRegister_
    )
        FeeFlowControllerNative(
            initPrice, wethAddress, paymentReceiver_, epochPeriod_, priceMultiplier_, minInitPrice_
        )
    {
        // check input
        if (incentiveBps_ > 10_000) {
            revert InvalidConfiguration(incentiveBps_);
        }

        if (minNativeBalanceForRegister_ == 0) {
            revert InvalidConfiguration(minNativeBalanceForRegister_);
        }

        // set config
        incentiveBps = incentiveBps_;
        minNativeBalanceForRegister = minNativeBalanceForRegister_;
    }

    /// @dev Sets up rewards on Beam staking contract using all native tokens held in the contract.
    /// @notice Caller receives an incentive for triggering this function; minimum native balance required.
    function registerBlockGasRewards() external virtual {
        // wrap native tokens into WETH
        uint256 wethAmount = _wrapAllNativeTokens();
        if (wethAmount < minNativeBalanceForRegister) {
            // require a minimum native balance in the contract to register rewards
            revert NativeBalanceTooLow(wethAmount);
        }

        // pay incentive to caller
        uint256 incentiveAmount = wethAmount / 10_000 * incentiveBps;
        if (incentiveAmount > 0) {
            paymentToken.safeTransfer(msg.sender, incentiveAmount);
        }

        // register remaining rewards on Beam staking contract
        _registerRewards(wethAmount - incentiveAmount);
    }

    /// @dev Wraps *all* native tokens locked in the contract into WETH.
    /// @return wethAmount The amount of native tokens wrapped.
    function _wrapAllNativeTokens() internal virtual returns (uint256 wethAmount) {
        // get native balance
        wethAmount = address(this).balance;
        if (wethAmount > 0) {
            // wrap all native tokens into WETH
            paymentToken.deposit{value: wethAmount}();
        }

        return wethAmount;
    }

    /// @dev Internal function to set up rewards on Beam staking contract.
    /// @param wethAmount The amount of WETH tokens to be registered as rewards.
    /// @notice Sets up WETH as staking rewards by calling `StakingMgr.registerProtocolRewards`.
    function _registerRewards(
        uint256 wethAmount
    ) internal virtual {
        // approve and register all WETH as rewards on Beam staking contract
        if (wethAmount > 0) {
            // approve WETH transfer to Beam staking contract
            paymentToken.approve(paymentReceiver, wethAmount);

            // setup rewards on Beam staking contract
            IStakingManagerMinimal(paymentReceiver)
                .registerProtocolRewards(address(paymentToken), wethAmount);
        }
    }

    /// @dev Override handling native token payments.
    function _handleNativePayment(
        address, /* sender */
        uint256 /* paymentAmount */
    ) internal virtual override {
        // setup rewards on Beam staking contract
        _registerRewards(_wrapAllNativeTokens());
    }

    /// @dev Override handling ERC20 token payments.
    /// @param sender The address sending the payment.
    /// @param paymentAmount The amount of ERC20 tokens to be handled.
    function _handleERC20Payment(
        address sender,
        uint256 paymentAmount
    ) internal virtual override {
        if (paymentAmount > 0) {
            /// Payment in WETH (ERC20) tokens - transfer WETH from buyer to auction contract
            paymentToken.safeTransferFrom(sender, address(this), paymentAmount);
        }

        // setup rewards on Beam staking contract
        _registerRewards(_wrapAllNativeTokens() + paymentAmount);
    }
}
