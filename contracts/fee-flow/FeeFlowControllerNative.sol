// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.25;

import {ERC20} from "@solmate/tokens/ERC20.sol";
import {WETH} from "@solmate/tokens/WETH.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";

/// @title FeeFlowControllerNative
/// @author Euler Labs (https://eulerlabs.com) / Native token support by xtools-at @ Beam Labs
/// @notice Continuous back to back dutch auctions selling any asset received by this contract
/// @dev Patched version supports payments in native tokens and WETH **only**!
contract FeeFlowControllerNative {
    using SafeTransferLib for ERC20;
    using SafeTransferLib for WETH;

    uint256 public constant MIN_EPOCH_PERIOD = 1 hours;
    uint256 public constant MAX_EPOCH_PERIOD = 365 days;
    uint256 public constant MIN_PRICE_MULTIPLIER = 1.1e18; // Should at least be 110% of settlement price
    uint256 public constant MAX_PRICE_MULTIPLIER = 3e18; // Should not exceed 300% of settlement price
    uint256 public constant ABS_MIN_INIT_PRICE = 1e6; // Minimum sane value for init price
    uint256 public constant ABS_MAX_INIT_PRICE = type(uint192).max; // chosen so that initPrice * priceMultiplier does not exceed uint256
    uint256 public constant PRICE_MULTIPLIER_SCALE = 1e18;

    WETH public immutable paymentToken; // PATCH: must be WETH
    address public immutable paymentReceiver;
    uint256 public immutable epochPeriod;
    uint256 public immutable priceMultiplier;
    uint256 public immutable minInitPrice;

    struct Slot0 {
        uint8 locked; // 1 if locked, 2 if unlocked
        uint16 epochId; // intentionally overflowable
        uint192 initPrice;
        uint40 startTime;
    }

    Slot0 internal slot0;

    event Buy(address indexed buyer, address indexed assetsReceiver, uint256 paymentAmount);

    error Reentrancy();
    error InitPriceBelowMin();
    error InitPriceExceedsMax();
    error EpochPeriodBelowMin();
    error EpochPeriodExceedsMax();
    error PriceMultiplierBelowMin();
    error PriceMultiplierExceedsMax();
    error MinInitPriceBelowMin();
    error MinInitPriceExceedsAbsMaxInitPrice();
    error DeadlinePassed();
    error EmptyAssets();
    error EpochIdMismatch();
    error MaxPaymentTokenAmountExceeded();
    error PaymentReceiverIsThis();
    error NativePaymentsOnly();

    modifier nonReentrant() {
        if (slot0.locked == 2) revert Reentrancy();
        slot0.locked = 2;
        _;
        slot0.locked = 1;
    }

    modifier nonReentrantView() {
        if (slot0.locked == 2) revert Reentrancy();
        _;
    }

    /// @dev Initializes the FeeFlowController contract with the specified parameters.
    /// @param initPrice The initial price for the first epoch.
    /// @param wethAddress The address of the WETH token contract (set to 0x0 to disable WETH payments).
    /// @param paymentReceiver_ The address of the payment receiver.
    /// @param epochPeriod_ The duration of each epoch period.
    /// @param priceMultiplier_ The multiplier for adjusting the price from one epoch to the next.
    /// @param minInitPrice_ The minimum allowed initial price for an epoch.
    /// @notice This constructor performs parameter validation and sets the initial values for the contract.
    constructor(
        uint256 initPrice,
        address wethAddress, // PATCH: paymentToken must be WETH
        address paymentReceiver_,
        uint256 epochPeriod_,
        uint256 priceMultiplier_,
        uint256 minInitPrice_
    ) {
        if (initPrice < minInitPrice_) revert InitPriceBelowMin();
        if (initPrice > ABS_MAX_INIT_PRICE) revert InitPriceExceedsMax();
        if (epochPeriod_ < MIN_EPOCH_PERIOD) revert EpochPeriodBelowMin();
        if (epochPeriod_ > MAX_EPOCH_PERIOD) revert EpochPeriodExceedsMax();
        if (priceMultiplier_ < MIN_PRICE_MULTIPLIER) revert PriceMultiplierBelowMin();
        if (priceMultiplier_ > MAX_PRICE_MULTIPLIER) revert PriceMultiplierExceedsMax();
        if (minInitPrice_ < ABS_MIN_INIT_PRICE) revert MinInitPriceBelowMin();
        if (minInitPrice_ > ABS_MAX_INIT_PRICE) revert MinInitPriceExceedsAbsMaxInitPrice();
        if (paymentReceiver_ == address(this)) revert PaymentReceiverIsThis();

        slot0.initPrice = uint192(initPrice);
        slot0.startTime = uint40(block.timestamp);

        paymentToken = WETH(payable(wethAddress));
        paymentReceiver = paymentReceiver_;
        epochPeriod = epochPeriod_;
        priceMultiplier = priceMultiplier_;
        minInitPrice = minInitPrice_;
    }

    /// @dev Allows a user to buy assets by sending native tokens and receiving the assets.
    /// @param assets The addresses of the assets to be bought.
    /// @param assetsReceiver The address that will receive the bought assets.
    /// @param epochId Id of the epoch to buy from, will revert if not the current epoch
    /// @param deadline The deadline timestamp for the purchase.
    /// @return paymentAmount The amount of native tokens transferred for the purchase.
    function buyNative(
        address[] calldata assets,
        address assetsReceiver,
        uint256 epochId,
        uint256 deadline
    ) external payable nonReentrant returns (uint256) {
        return _buy(assets, assetsReceiver, epochId, deadline, msg.value, true);
    }

    /// @dev Allows a user to buy assets by transferring payment tokens and receiving the assets.
    /// @param assets The addresses of the assets to be bought.
    /// @param assetsReceiver The address that will receive the bought assets.
    /// @param epochId Id of the epoch to buy from, will revert if not the current epoch
    /// @param deadline The deadline timestamp for the purchase.
    /// @param maxPaymentTokenAmount The maximum amount of payment tokens the user is willing to spend.
    /// @return paymentAmount The amount of payment tokens transferred for the purchase.
    /// @notice This function throws if the payment token is the zero address.
    function buy(
        address[] calldata assets,
        address assetsReceiver,
        uint256 epochId,
        uint256 deadline,
        uint256 maxPaymentTokenAmount
    ) external nonReentrant returns (uint256) {
        if (address(paymentToken) == address(0)) revert NativePaymentsOnly();

        return _buy(assets, assetsReceiver, epochId, deadline, maxPaymentTokenAmount, false);
    }

    /// @dev Internal helper to buy assets by transferring native/payment tokens and receiving the assets.
    /// @param assets The addresses of the assets to be bought.
    /// @param assetsReceiver The address that will receive the bought assets.
    /// @param epochId Id of the epoch to buy from, will revert if not the current epoch
    /// @param deadline The deadline timestamp for the purchase.
    /// @param maxPaymentAmount The maximum amount of tokens the user is willing to spend.
    /// @param isNativePayment Whether the payment is made in native tokens (true) or ERC20 tokens (false).
    /// @return paymentAmount The amount of payment tokens transferred for the purchase.
    /// @notice This function performs various checks and transfers the payment tokens to the payment receiver.
    /// It also transfers the assets to the assets receiver and sets up a new auction with an updated initial price.
    function _buy(
        address[] calldata assets,
        address assetsReceiver,
        uint256 epochId,
        uint256 deadline,
        uint256 maxPaymentAmount,
        bool isNativePayment
    ) internal returns (uint256 paymentAmount) {
        if (block.timestamp > deadline) revert DeadlinePassed();
        if (assets.length == 0) revert EmptyAssets();

        Slot0 memory slot0Cache = slot0;

        if (uint16(epochId) != slot0Cache.epochId) revert EpochIdMismatch();

        address sender = msg.sender; // PATCH: removed EVCUtil dependency

        paymentAmount = _getPriceFromCache(slot0Cache);

        if (paymentAmount > maxPaymentAmount) revert MaxPaymentTokenAmountExceeded();

        /// PATCH: Transfer native tokens to payment receiver
        if (isNativePayment) {
            /// Payment in native tokens
            if (paymentAmount > 0) {
                // send native tokens to payment receiver
                SafeTransferLib.safeTransferETH(paymentReceiver, paymentAmount);
            }

            // send back excess native tokens
            if (maxPaymentAmount > paymentAmount) {
                SafeTransferLib.safeTransferETH(sender, maxPaymentAmount - paymentAmount);
            }
        } else if (paymentAmount > 0) {
            /// Payment in WETH (ERC20) tokens
            // transfer WETH from buyer to auction contract
            paymentToken.safeTransferFrom(sender, address(this), paymentAmount);

            // unwrap WETH tokens
            paymentToken.withdraw(paymentAmount);

            // send native tokens to payment receiver
            SafeTransferLib.safeTransferETH(paymentReceiver, paymentAmount);
        }

        for (uint256 i = 0; i < assets.length; ++i) {
            // Transfer full balance to buyer
            uint256 balance = ERC20(assets[i]).balanceOf(address(this));
            ERC20(assets[i]).safeTransfer(assetsReceiver, balance);
        }

        // Setup new auction
        uint256 newInitPrice = paymentAmount * priceMultiplier / PRICE_MULTIPLIER_SCALE;

        if (newInitPrice > ABS_MAX_INIT_PRICE) {
            newInitPrice = ABS_MAX_INIT_PRICE;
        } else if (newInitPrice < minInitPrice) {
            newInitPrice = minInitPrice;
        }

        // epochID is allowed to overflow, effectively reusing them
        unchecked {
            slot0Cache.epochId++;
        }
        slot0Cache.initPrice = uint192(newInitPrice);
        slot0Cache.startTime = uint40(block.timestamp);

        // Write cache in single write
        slot0 = slot0Cache;

        emit Buy(sender, assetsReceiver, paymentAmount);

        return paymentAmount;
    }

    /// @dev Retrieves the current price from the cache based on the elapsed time since the start of the epoch.
    /// @param slot0Cache The Slot0 struct containing the initial price and start time of the epoch.
    /// @return price The current price calculated based on the elapsed time and the initial price.
    /// @notice This function calculates the current price by subtracting a fraction of the initial price based on the elapsed time.
    // If the elapsed time exceeds the epoch period, the price will be 0.
    function _getPriceFromCache(
        Slot0 memory slot0Cache
    ) internal view returns (uint256) {
        uint256 timePassed = block.timestamp - slot0Cache.startTime;

        if (timePassed > epochPeriod) {
            return 0;
        }

        return slot0Cache.initPrice - slot0Cache.initPrice * timePassed / epochPeriod;
    }

    /// @dev Calculates the current price
    /// @return price The current price calculated based on the elapsed time and the initial price.
    /// @notice Uses the internal function `_getPriceFromCache` to calculate the current price.
    function getPrice() external view nonReentrantView returns (uint256) {
        return _getPriceFromCache(slot0);
    }

    /// @dev Retrieves Slot0 as a memory struct
    /// @return Slot0 The Slot0 value as a Slot0 struct
    function getSlot0() external view nonReentrantView returns (Slot0 memory) {
        return slot0;
    }
}
