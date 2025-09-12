// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import "forge-std/Test.sol";
import "./lib/MockToken.sol";
import "./lib/ReenteringMockToken.sol";
import "./lib/PredictAddress.sol";
import "./lib/OverflowableEpochIdFeeFlowController.sol";
import "../FeeFlowControllerNative.sol";
import {WETH} from "@solmate/tokens/WETH.sol";

contract FeeFlowControllerTest is Test {
    uint256 public constant INIT_PRICE = 1e18;
    uint256 public constant MIN_INIT_PRICE = 1e6;
    uint256 public constant EPOCH_PERIOD = 14 days;
    uint256 public constant PRICE_MULTIPLIER = 2e18;

    address public paymentReceiver = makeAddr("paymentReceiver");
    address public buyer = makeAddr("buyer");
    address public assetsReceiver = makeAddr("assetsReceiver");

    WETH paymentToken;
    MockToken token1;
    MockToken token2;
    MockToken token3;
    MockToken token4;
    MockToken[] public tokens;

    FeeFlowControllerNative public feeFlowController;

    function setUp() public {
        // Deploy tokens
        paymentToken = new WETH();
        vm.label(address(paymentToken), "paymentToken");
        token1 = new MockToken("Token 1", "T1");
        vm.label(address(token1), "token1");
        tokens.push(token1);
        token2 = new MockToken("Token 2", "T2");
        vm.label(address(token2), "token2");
        tokens.push(token2);
        token3 = new MockToken("Token 3", "T3");
        vm.label(address(token3), "token3");
        tokens.push(token3);
        token4 = new MockToken("Token 4", "T4");
        vm.label(address(token4), "token4");
        tokens.push(token4);

        // Deploy FeeFlowController
        feeFlowController = new FeeFlowControllerNative(
            INIT_PRICE,
            address(paymentToken),
            paymentReceiver,
            EPOCH_PERIOD,
            PRICE_MULTIPLIER,
            MIN_INIT_PRICE
        );

        // Mint payment tokens to buyer
        _mintWeth(buyer, 1000000e18);
        // Approve payment token from buyer to FeeFlowController
        vm.startPrank(buyer);
        paymentToken.approve(address(feeFlowController), type(uint256).max);
        vm.stopPrank();
    }

    function _mintWeth(address receiver, uint256 amount) internal {
        vm.deal(receiver, amount);
        vm.prank(receiver);
        paymentToken.deposit{value: amount}();
    }

    function testConstructor() public view {
        FeeFlowControllerNative.Slot0 memory slot0 = feeFlowController.getSlot0();
        assertEq(slot0.initPrice, uint128(INIT_PRICE));
        assertEq(slot0.startTime, block.timestamp);
        assertEq(address(feeFlowController.paymentToken()), address(paymentToken));
        assertEq(feeFlowController.paymentReceiver(), paymentReceiver);
        assertEq(feeFlowController.epochPeriod(), EPOCH_PERIOD);
        assertEq(feeFlowController.priceMultiplier(), PRICE_MULTIPLIER);
        assertEq(feeFlowController.minInitPrice(), MIN_INIT_PRICE);
    }

    function testConstructorInitPriceBelowMin() public {
        vm.expectRevert(FeeFlowControllerNative.InitPriceBelowMin.selector);
        new FeeFlowControllerNative(
            MIN_INIT_PRICE - 1,
            address(paymentToken),
            paymentReceiver,
            EPOCH_PERIOD,
            PRICE_MULTIPLIER,
            MIN_INIT_PRICE
        );
    }

    function testConstructorEpochPeriodBelowMin() public {
        uint256 minEpochPeriod = feeFlowController.MIN_EPOCH_PERIOD();
        vm.expectRevert(FeeFlowControllerNative.EpochPeriodBelowMin.selector);
        new FeeFlowControllerNative(
            INIT_PRICE,
            address(paymentToken),
            paymentReceiver,
            minEpochPeriod - 1,
            PRICE_MULTIPLIER,
            MIN_INIT_PRICE
        );
    }

    function testConstructorEpochPeriodExceedsMax() public {
        uint256 maxEpochPeriod = feeFlowController.MAX_EPOCH_PERIOD();
        vm.expectRevert(FeeFlowControllerNative.EpochPeriodExceedsMax.selector);
        new FeeFlowControllerNative(
            INIT_PRICE,
            address(paymentToken),
            paymentReceiver,
            maxEpochPeriod + 1,
            PRICE_MULTIPLIER,
            MIN_INIT_PRICE
        );
    }

    function testConstructorPriceMultiplierBelowMin() public {
        uint256 minPriceMultiplier = feeFlowController.MIN_PRICE_MULTIPLIER();
        vm.expectRevert(FeeFlowControllerNative.PriceMultiplierBelowMin.selector);
        new FeeFlowControllerNative(
            INIT_PRICE,
            address(paymentToken),
            paymentReceiver,
            EPOCH_PERIOD,
            minPriceMultiplier - 1,
            MIN_INIT_PRICE
        );
    }

    function testConstructorMinInitPriceBelowMin() public {
        uint256 absMinInitPrice = feeFlowController.ABS_MIN_INIT_PRICE();
        vm.expectRevert(FeeFlowControllerNative.MinInitPriceBelowMin.selector);
        new FeeFlowControllerNative(
            INIT_PRICE,
            address(paymentToken),
            paymentReceiver,
            EPOCH_PERIOD,
            PRICE_MULTIPLIER,
            absMinInitPrice - 1
        );
    }

    function testConstructorMinInitPriceExceedsABSMaxInitPrice() public {
        // Fails at init price check
        vm.expectRevert(FeeFlowControllerNative.InitPriceExceedsMax.selector);
        new FeeFlowControllerNative(
            uint256(type(uint216).max) + 2,
            address(paymentToken),
            paymentReceiver,
            EPOCH_PERIOD,
            PRICE_MULTIPLIER,
            uint256(type(uint216).max) + 1
        );
    }

    function testConstructorPaymentReceiverIsThis() public {
        address deployer = makeAddr("deployer");
        address expectedAddress = PredictAddress.calc(deployer, 0);

        vm.startPrank(deployer);
        vm.expectRevert(FeeFlowControllerNative.PaymentReceiverIsThis.selector);
        new FeeFlowControllerNative(
            INIT_PRICE,
            address(paymentToken),
            expectedAddress,
            EPOCH_PERIOD,
            PRICE_MULTIPLIER,
            MIN_INIT_PRICE
        );
        vm.stopPrank();
    }

    function testBuyStartOfAuction() public {
        mintTokensToBatchBuyer();

        uint256 paymentReceiverBalanceBefore = paymentReceiver.balance;
        uint256 buyerBalanceBefore = paymentToken.balanceOf(buyer);

        uint256 expectedPrice = feeFlowController.getPrice();

        vm.startPrank(buyer);
        feeFlowController.buy(
            assetsAddresses(), assetsReceiver, 0, block.timestamp + 1 days, 1000000e18
        );
        vm.stopPrank();

        uint256 paymentReceiverBalanceAfter = paymentReceiver.balance;
        uint256 buyerBalanceAfter = paymentToken.balanceOf(buyer);
        FeeFlowControllerNative.Slot0 memory slot0 = feeFlowController.getSlot0();

        // Assert token balances
        assert0Balances(address(feeFlowController));
        assertMintBalances(assetsReceiver);
        assertEq(expectedPrice, INIT_PRICE);
        assertEq(paymentReceiverBalanceAfter, paymentReceiverBalanceBefore + expectedPrice);
        assertEq(buyerBalanceAfter, buyerBalanceBefore - expectedPrice);

        // Assert new auctionState
        assertEq(slot0.epochId, uint8(1));
        assertEq(slot0.initPrice, uint128(INIT_PRICE * 2));
        assertEq(slot0.startTime, block.timestamp);
    }

    function testBuyEndOfAuction() public {
        mintTokensToBatchBuyer();

        uint256 paymentReceiverBalanceBefore = paymentReceiver.balance;
        uint256 buyerBalanceBefore = paymentToken.balanceOf(buyer);

        // Skip to end of auction and then some
        skip(EPOCH_PERIOD + 1 days);
        uint256 expectedPrice = feeFlowController.getPrice();

        vm.startPrank(buyer);
        feeFlowController.buy(
            assetsAddresses(), assetsReceiver, 0, block.timestamp + 1 days, 1000000e18
        );
        vm.stopPrank();

        uint256 paymentReceiverBalanceAfter = paymentReceiver.balance;
        uint256 buyerBalanceAfter = paymentToken.balanceOf(buyer);
        FeeFlowControllerNative.Slot0 memory slot0 = feeFlowController.getSlot0();

        // Assert token balances
        assert0Balances(address(feeFlowController));
        assertMintBalances(assetsReceiver);
        // Should have paid 0
        assertEq(expectedPrice, 0);
        assertEq(paymentReceiverBalanceAfter, paymentReceiverBalanceBefore);
        assertEq(buyerBalanceAfter, buyerBalanceBefore);

        // Assert new auctionState
        assertEq(slot0.epochId, uint8(1));
        assertEq(slot0.initPrice, MIN_INIT_PRICE);
        assertEq(slot0.startTime, block.timestamp);
    }

    function testBuyMiddleOfAuction() public {
        mintTokensToBatchBuyer();

        uint256 paymentReceiverBalanceBefore = paymentReceiver.balance;
        uint256 buyerBalanceBefore = paymentToken.balanceOf(buyer);

        // Skip to middle of auction
        skip(EPOCH_PERIOD / 2);
        uint256 expectedPrice = feeFlowController.getPrice();

        vm.startPrank(buyer);
        feeFlowController.buy(
            assetsAddresses(), assetsReceiver, 0, block.timestamp + 1 days, 1000000e18
        );
        vm.stopPrank();

        uint256 paymentReceiverBalanceAfter = paymentReceiver.balance;
        uint256 buyerBalanceAfter = paymentToken.balanceOf(buyer);
        FeeFlowControllerNative.Slot0 memory slot0 = feeFlowController.getSlot0();

        // Assert token balances
        assert0Balances(address(feeFlowController));
        assertMintBalances(assetsReceiver);
        assertEq(expectedPrice, INIT_PRICE / 2);
        assertEq(paymentReceiverBalanceAfter, paymentReceiverBalanceBefore + expectedPrice);
        assertEq(buyerBalanceAfter, buyerBalanceBefore - expectedPrice);

        // Assert new auctionState
        assertEq(slot0.epochId, uint8(1));
        assertEq(slot0.initPrice, uint128(INIT_PRICE));
        assertEq(slot0.startTime, block.timestamp);
    }

    function testBuyDeadlinePassedShouldFail() public {
        mintTokensToBatchBuyer();
        skip(365 days);

        vm.startPrank(buyer);
        vm.expectRevert(FeeFlowControllerNative.DeadlinePassed.selector);
        feeFlowController.buy(
            assetsAddresses(), assetsReceiver, 0, block.timestamp - 1 days, 1000000e18
        );
        vm.stopPrank();

        // Double check tokens haven't moved
        assertMintBalances(address(feeFlowController));
    }

    function testBuyEmptyAssetsShouldFail() public {
        mintTokensToBatchBuyer();

        vm.startPrank(buyer);
        vm.expectRevert(FeeFlowControllerNative.EmptyAssets.selector);
        feeFlowController.buy(
            new address[](0), assetsReceiver, 0, block.timestamp + 1 days, 1000000e18
        );
        vm.stopPrank();

        // Double check tokens haven't moved
        assertMintBalances(address(feeFlowController));
    }

    function testBuyWrongEpochShouldFail() public {
        mintTokensToBatchBuyer();

        // Is actually at 0
        uint256 epochId = 1;

        vm.startPrank(buyer);
        vm.expectRevert(FeeFlowControllerNative.EpochIdMismatch.selector);
        feeFlowController.buy(
            assetsAddresses(), assetsReceiver, epochId, block.timestamp + 1 days, 1000000e18
        );
        vm.stopPrank();

        // Double check tokens haven't moved
        assertMintBalances(address(feeFlowController));
    }

    function testBuyPaymentAmountExceedsMax() public {
        mintTokensToBatchBuyer();

        vm.startPrank(buyer);
        vm.expectRevert(FeeFlowControllerNative.MaxPaymentTokenAmountExceeded.selector);
        feeFlowController.buy(
            assetsAddresses(), assetsReceiver, 0, block.timestamp + 1 days, INIT_PRICE / 2
        );
        vm.stopPrank();

        // Double check tokens haven't moved
        assertMintBalances(address(feeFlowController));
    }

    function testBuyReenter() public {
        uint256 mintAmount = 1e18;

        // Setup reentering token
        ReenteringMockToken reenterToken = new ReenteringMockToken("ReenteringToken", "RET");
        reenterToken.mint(address(feeFlowController), mintAmount);
        reenterToken.setReenterTargetAndData(
            address(feeFlowController),
            abi.encodeWithSelector(
                feeFlowController.buy.selector,
                assetsAddresses(),
                assetsReceiver,
                block.timestamp + 1 days,
                1000000e18
            )
        );

        address[] memory assets = new address[](1);
        assets[0] = address(reenterToken);

        vm.startPrank(buyer);
        // Token does not bubble up error so this is the expected error on reentry
        vm.expectRevert("TRANSFER_FAILED");
        feeFlowController.buy(assets, assetsReceiver, 0, block.timestamp + 1 days, 1000000e18);
        vm.stopPrank();
    }

    function testBuyReenterGetPrice() public {
        uint256 mintAmount = 1e18;

        // Setup reentering token
        ReenteringMockToken reenterToken = new ReenteringMockToken("ReenteringToken", "RET");
        reenterToken.mint(address(feeFlowController), mintAmount);
        reenterToken.setReenterTargetAndData(
            address(feeFlowController), abi.encodeWithSelector(feeFlowController.getPrice.selector)
        );

        address[] memory assets = new address[](1);
        assets[0] = address(reenterToken);

        vm.startPrank(buyer);
        // Token does not bubble up error so this is the expected error on reentry
        vm.expectRevert("TRANSFER_FAILED");
        feeFlowController.buy(assets, assetsReceiver, 0, block.timestamp + 1 days, 1000000e18);
        vm.stopPrank();
    }

    function testBuyReenterGetSlot0() public {
        uint256 mintAmount = 1e18;

        // Setup reentering token
        ReenteringMockToken reenterToken = new ReenteringMockToken("ReenteringToken", "RET");
        reenterToken.mint(address(feeFlowController), mintAmount);
        reenterToken.setReenterTargetAndData(
            address(feeFlowController), abi.encodeWithSelector(feeFlowController.getSlot0.selector)
        );

        address[] memory assets = new address[](1);
        assets[0] = address(reenterToken);

        vm.startPrank(buyer);
        // Token does not bubble up error so this is the expected error on reentry
        vm.expectRevert("TRANSFER_FAILED");
        feeFlowController.buy(assets, assetsReceiver, 0, block.timestamp + 1 days, 1000000e18);
        vm.stopPrank();
    }

    function testBuyInitPriceExceedingABS_MAX_INIT_PRICE() public {
        uint256 absMaxInitPrice = feeFlowController.ABS_MAX_INIT_PRICE();

        // Deploy with auction at max init price
        FeeFlowControllerNative tempFeeFlowController = new FeeFlowControllerNative(
            absMaxInitPrice,
            address(paymentToken),
            paymentReceiver,
            EPOCH_PERIOD,
            1.1e18,
            absMaxInitPrice
        );

        // Mint payment tokens to buyer
        _mintWeth(buyer, type(uint216).max);

        vm.startPrank(buyer);
        // Approve payment token from buyer to FeeFlowController
        paymentToken.approve(address(tempFeeFlowController), type(uint256).max);
        // Buy
        tempFeeFlowController.buy(
            assetsAddresses(), assetsReceiver, 0, block.timestamp + 1 days, type(uint216).max
        );
        vm.stopPrank();

        // Assert new init price
        FeeFlowControllerNative.Slot0 memory slot0 = tempFeeFlowController.getSlot0();
        assertEq(slot0.initPrice, uint216(absMaxInitPrice));
    }

    function testBuyWrapAroundEpochId() public {
        // MINT a lot of tokens
        _mintWeth(buyer, type(uint256).max - paymentToken.balanceOf(buyer));

        OverflowableEpochIdFeeFlowController tempFeeFlowController = new OverflowableEpochIdFeeFlowController(
            MIN_INIT_PRICE,
            address(paymentToken),
            paymentReceiver,
            EPOCH_PERIOD,
            PRICE_MULTIPLIER,
            MIN_INIT_PRICE
        );
        tempFeeFlowController.setEpochId(type(uint16).max);

        vm.startPrank(buyer);
        paymentToken.approve(address(tempFeeFlowController), type(uint256).max);
        tempFeeFlowController.buy(
            assetsAddresses(),
            assetsReceiver,
            type(uint16).max,
            block.timestamp + 1 days,
            type(uint256).max
        );
        vm.stopPrank();

        FeeFlowControllerNative.Slot0 memory slot0 = feeFlowController.getSlot0();
        assertEq(slot0.epochId, uint16(0));
    }

    // Testing for overflows in price calculations --------------------------------
    function testMAX_INIT_PRICEandMAX_EPOCH_PERIODdoNotOverflowPricing() public {
        uint256 absMaxInitPrice = feeFlowController.ABS_MAX_INIT_PRICE();
        uint256 maxEpochPeriod = feeFlowController.MAX_EPOCH_PERIOD();

        FeeFlowControllerNative tempFeeFlowController = new FeeFlowControllerNative(
            absMaxInitPrice,
            address(paymentToken),
            paymentReceiver,
            maxEpochPeriod,
            1.1e18,
            absMaxInitPrice
        );
        _mintWeth(buyer, absMaxInitPrice);

        skip(maxEpochPeriod);

        vm.startPrank(buyer);
        paymentToken.approve(address(tempFeeFlowController), type(uint256).max);

        // Since timePassed == epochPeriod, timePassed will be multiplied to epochPeriod.
        // Does this not overflow and return zero?
        assert(tempFeeFlowController.getPrice() == 0);
        vm.stopPrank();
    }

    function testMAX_INIT_PRICEandMAX_EPOCH_PERIODminusOneDoNotOverflowPricing() public {
        uint256 absMaxInitPrice = feeFlowController.ABS_MAX_INIT_PRICE();
        uint256 maxEpochPeriod = feeFlowController.MAX_EPOCH_PERIOD();

        FeeFlowControllerNative tempFeeFlowController = new FeeFlowControllerNative(
            absMaxInitPrice,
            address(paymentToken),
            paymentReceiver,
            maxEpochPeriod,
            1.1e18,
            absMaxInitPrice
        );
        _mintWeth(buyer, absMaxInitPrice);

        skip(maxEpochPeriod - 1);

        vm.startPrank(buyer);
        paymentToken.approve(address(tempFeeFlowController), type(uint256).max);

        // Since timePassed < epochPeriod, timePassed will be multiplied to epochPeriod.
        // Does this not overflow?
        tempFeeFlowController.getPrice();
        vm.stopPrank();
    }

    function testMAX_INIT_PRICEandMAX_PRICE_MULTIPLIERdoNotOverflowNextAuction() public {
        uint256 absMaxInitPrice = feeFlowController.ABS_MAX_INIT_PRICE();
        uint256 maxPriceMultiplier = feeFlowController.MAX_PRICE_MULTIPLIER();

        FeeFlowControllerNative tempFeeFlowController = new FeeFlowControllerNative(
            absMaxInitPrice,
            address(paymentToken),
            paymentReceiver,
            EPOCH_PERIOD,
            maxPriceMultiplier,
            absMaxInitPrice
        );
        _mintWeth(buyer, absMaxInitPrice);

        vm.startPrank(buyer);
        paymentToken.approve(address(tempFeeFlowController), type(uint256).max);

        // Purchase will initialize the next auction and increase the price by its multiplier. Doesn't it revert?
        assert(
            tempFeeFlowController.buy(
                assetsAddresses(), assetsReceiver, 0, block.timestamp + 1 days, type(uint216).max
            ) == absMaxInitPrice
        );
        // Its next price should be capped to the maximum init price
        assert(tempFeeFlowController.getPrice() == absMaxInitPrice);
        vm.stopPrank();
    }

    // Native token specific tests ------------------------------------------------
    function testBuyNativeStartOfAuction() public {
        mintTokensToBatchBuyer();

        uint256 paymentReceiverBalanceBefore = paymentReceiver.balance;
        uint256 buyerBalanceBefore = 1 ether;
        uint256 expectedPrice = feeFlowController.getPrice();

        vm.deal(buyer, expectedPrice + 1 ether); // Give buyer enough ETH
        vm.startPrank(buyer);
        uint256 paymentAmount = feeFlowController.buyNative{value: expectedPrice + 1 ether}(
            assetsAddresses(), assetsReceiver, 0, block.timestamp + 1 days
        );
        vm.stopPrank();

        uint256 paymentReceiverBalanceAfter = paymentReceiver.balance;
        uint256 buyerBalanceAfter = buyer.balance;
        FeeFlowControllerNative.Slot0 memory slot0 = feeFlowController.getSlot0();

        assert0Balances(address(feeFlowController));
        assertMintBalances(assetsReceiver);
        assertEq(paymentAmount, expectedPrice);
        assertEq(paymentReceiverBalanceAfter, paymentReceiverBalanceBefore + expectedPrice);
        // Buyer should get excess refunded
        assertEq(buyerBalanceAfter, buyerBalanceBefore);
        assertEq(slot0.epochId, uint8(1));
        assertEq(slot0.initPrice, uint128(INIT_PRICE * 2));
        assertEq(slot0.startTime, block.timestamp);
    }

    function testBuyNativeEndOfAuction() public {
        mintTokensToBatchBuyer();

        uint256 paymentReceiverBalanceBefore = paymentReceiver.balance;
        uint256 buyerBalanceBefore = buyer.balance;

        skip(EPOCH_PERIOD + 1 days);
        uint256 expectedPrice = feeFlowController.getPrice();

        vm.deal(buyer, 1 ether);
        vm.startPrank(buyer);
        uint256 paymentAmount = feeFlowController.buyNative{value: 1 ether}(
            assetsAddresses(), assetsReceiver, 0, block.timestamp + 1 days
        );
        vm.stopPrank();

        uint256 paymentReceiverBalanceAfter = paymentReceiver.balance;
        uint256 buyerBalanceAfter = buyer.balance;
        FeeFlowControllerNative.Slot0 memory slot0 = feeFlowController.getSlot0();

        assert0Balances(address(feeFlowController));
        assertMintBalances(assetsReceiver);
        assertEq(expectedPrice, 0);
        assertEq(paymentAmount, 0);
        assertEq(paymentReceiverBalanceAfter, paymentReceiverBalanceBefore);
        assertEq(buyerBalanceAfter - 1 ether, buyerBalanceBefore);
        assertEq(slot0.epochId, uint8(1));
        assertEq(slot0.initPrice, MIN_INIT_PRICE);
        assertEq(slot0.startTime, block.timestamp);
    }

    function testBuyNativeDeadlinePassedShouldFail() public {
        mintTokensToBatchBuyer();
        skip(365 days);

        vm.deal(buyer, 1 ether);
        vm.startPrank(buyer);
        vm.expectRevert(FeeFlowControllerNative.DeadlinePassed.selector);
        feeFlowController.buyNative{value: 1 ether}(
            assetsAddresses(), assetsReceiver, 0, block.timestamp - 1 days
        );
        vm.stopPrank();

        assertMintBalances(address(feeFlowController));
    }

    function testBuyNativeEmptyAssetsShouldFail() public {
        mintTokensToBatchBuyer();

        vm.deal(buyer, 1 ether);
        vm.startPrank(buyer);
        vm.expectRevert(FeeFlowControllerNative.EmptyAssets.selector);
        feeFlowController.buyNative{value: 1 ether}(
            new address[](0), assetsReceiver, 0, block.timestamp + 1 days
        );
        vm.stopPrank();

        assertMintBalances(address(feeFlowController));
    }

    function testBuyNativeWrongEpochShouldFail() public {
        mintTokensToBatchBuyer();

        vm.deal(buyer, 1 ether);
        vm.startPrank(buyer);
        vm.expectRevert(FeeFlowControllerNative.EpochIdMismatch.selector);
        feeFlowController.buyNative{value: 1 ether}(
            assetsAddresses(), assetsReceiver, 1, block.timestamp + 1 days
        );
        vm.stopPrank();

        assertMintBalances(address(feeFlowController));
    }

    function testBuyNativeRefundsExcessETH() public {
        mintTokensToBatchBuyer();

        uint256 expectedPrice = feeFlowController.getPrice();
        uint256 excess = 1 ether;
        uint256 totalSent = expectedPrice + excess;

        vm.deal(buyer, totalSent);
        uint256 buyerBalanceBefore = buyer.balance;

        vm.startPrank(buyer);
        feeFlowController.buyNative{value: totalSent}(
            assetsAddresses(), assetsReceiver, 0, block.timestamp + 1 days
        );
        vm.stopPrank();

        uint256 buyerBalanceAfter = buyer.balance;
        // Buyer should only pay expectedPrice, excess refunded
        assertEq(buyerBalanceAfter, buyerBalanceBefore - expectedPrice);
    }

    function testBuyNativeZeroPayment() public {
        mintTokensToBatchBuyer();

        skip(EPOCH_PERIOD + 1 days);

        vm.deal(buyer, 1 ether);
        uint256 buyerBalanceBefore = buyer.balance;

        vm.startPrank(buyer);
        uint256 paymentAmount = feeFlowController.buyNative{value: 1 ether}(
            assetsAddresses(), assetsReceiver, 0, block.timestamp + 1 days
        );
        vm.stopPrank();

        uint256 buyerBalanceAfter = buyer.balance;
        // Should pay nothing, all ETH refunded
        assertEq(paymentAmount, 0);
        assertEq(buyerBalanceAfter, buyerBalanceBefore);
    }

    function testFuzzBuyNativePayment(
        uint256 extraEth
    ) public {
        mintTokensToBatchBuyer();

        uint256 expectedPrice = feeFlowController.getPrice();
        uint256 sentEth = expectedPrice + (extraEth % 1 ether);

        vm.deal(buyer, sentEth);
        uint256 buyerBalanceBefore = buyer.balance;

        vm.startPrank(buyer);
        uint256 paymentAmount = feeFlowController.buyNative{value: sentEth}(
            assetsAddresses(), assetsReceiver, 0, block.timestamp + 1 days
        );
        vm.stopPrank();

        uint256 buyerBalanceAfter = buyer.balance;
        assertEq(paymentAmount, expectedPrice);
        assertEq(buyerBalanceAfter, buyerBalanceBefore - expectedPrice);
        assert0Balances(address(feeFlowController));
        assertMintBalances(assetsReceiver);
    }

    function testFuzzBuyNativeDeadline(
        uint256 fuzzDeadline
    ) public {
        mintTokensToBatchBuyer();

        uint256 expectedPrice = feeFlowController.getPrice();
        vm.deal(buyer, expectedPrice);

        uint256 deadline = block.timestamp + (fuzzDeadline % 30 days);

        vm.startPrank(buyer);
        if (block.timestamp > deadline) {
            vm.expectRevert(FeeFlowControllerNative.DeadlinePassed.selector);
        }
        feeFlowController.buyNative{value: expectedPrice}(
            assetsAddresses(), assetsReceiver, 0, deadline
        );
        vm.stopPrank();
    }

    function testFuzzBuyNativeEpochId(
        uint256 fuzzEpochId
    ) public {
        mintTokensToBatchBuyer();

        uint256 expectedPrice = feeFlowController.getPrice();
        vm.deal(buyer, expectedPrice);

        vm.startPrank(buyer);
        if (fuzzEpochId != 0) {
            vm.expectRevert(FeeFlowControllerNative.EpochIdMismatch.selector);
        }
        feeFlowController.buyNative{value: expectedPrice}(
            assetsAddresses(), assetsReceiver, fuzzEpochId, block.timestamp + 1 days
        );
        vm.stopPrank();
    }

    // Helper functions -----------------------------------------------------
    function mintTokensToBatchBuyer() public {
        for (uint256 i = 0; i < tokens.length; i++) {
            tokens[i].mint(address(feeFlowController), 1000000e18 * (i + 1));
        }
    }

    function mintAmounts() public view returns (uint256[] memory amounts) {
        amounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            amounts[i] = 1000000e18 * (i + 1);
        }
        return amounts;
    }

    function assetsAddresses() public view returns (address[] memory addresses) {
        addresses = new address[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            addresses[i] = address(tokens[i]);
        }
        return addresses;
    }

    function assetsBalances(
        address who
    ) public view returns (uint256[] memory result) {
        result = new uint256[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            result[i] = tokens[i].balanceOf(who);
        }

        return result;
    }

    function assertMintBalances(
        address who
    ) public view {
        uint256[] memory mintAmounts_ = mintAmounts();
        uint256[] memory balances = assetsBalances(who);

        for (uint256 i = 0; i < tokens.length; i++) {
            assertEq(balances[i], mintAmounts_[i]);
        }
    }

    function assert0Balances(
        address who
    ) public view {
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 balance = tokens[i].balanceOf(who);
            assertEq(balance, 0);
        }
    }
}
