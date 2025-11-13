// SPDX-License-Identifier: MIT
// run via `forge test -vvv --match-path "contracts/fee-flow/test/FeeFlowRewardsFork.t.sol"`
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {WETH} from "@solmate/tokens/WETH.sol";
import {FeeFlowRewards} from "../extensions/FeeFlowRewards.sol";
import {
    Native721TokenStakingManager
} from "../../validator-manager/Native721TokenStakingManager.sol";
import "./lib/MockToken.sol";

contract FeeFlowBeamForkTest is Test {
    // Network fork configuration
    string constant forkRpc = "https://subnets.avax.network/beam/mainnet/rpc";
    uint256 constant forkBlock = 6877141;
    // Contracts
    FeeFlowRewards ff;
    Native721TokenStakingManager constant pos =
        Native721TokenStakingManager(0x2FD428A5484d113294b44E69Cb9f269abC1d5B54);
    WETH constant weth = WETH(payable(0xD51BFa777609213A653a2CD067c9A0132a2D316A));
    // Accounts
    address constant safe = address(0x39C694A6f5c2987b9cE12FDc037b8d5E3c026aeC);
    address constant user = address(0xCA11E2);

    // Fee Flow config
    uint256 public constant INIT_PRICE = 100e18;
    uint256 public constant MIN_INIT_PRICE = 1e6;
    uint256 public constant EPOCH_PERIOD = 14 days;
    uint256 public constant PRICE_MULTIPLIER = 2e18;
    uint256 public constant INCENTIVE_BIPS = 1; // 0.01% incentive
    uint256 public constant MIN_REGISTER_BALANCE = 1 ether; // min 1 BEAM balance to register rewards

    // Mocks
    MockToken token1;
    MockToken token2;
    MockToken token3;
    MockToken token4;
    MockToken[] public tokens;

    // Args
    uint256 payment = INIT_PRICE;
    uint256 tokenAmount = 1000e18;

    function setUp() public {
        // Fork Beam mainnet
        vm.createSelectFork(forkRpc, forkBlock);
        vm.label(address(pos), "StakingManager");
        vm.label(address(weth), "WETH");
        vm.label(user, "User");
        vm.label(safe, "Safe");

        // Deploy Fee Flow Rewards
        ff = new FeeFlowRewards({
            initPrice: INIT_PRICE,
            wethAddress: address(weth),
            stakingManager_: address(pos),
            epochPeriod_: EPOCH_PERIOD,
            priceMultiplier_: PRICE_MULTIPLIER,
            minInitPrice_: MIN_INIT_PRICE,
            incentiveBps_: INCENTIVE_BIPS,
            minNativeBalanceForRegister_: MIN_REGISTER_BALANCE
        });
        vm.label(address(ff), "FeeFlowRewards");

        // Deploy tokens
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

        // Mint auctioned tokens to fee flow
        for (uint256 i = 0; i < tokens.length; i++) {
            tokens[i].mint(address(ff), tokenAmount * (i + 1));
        }

        // Fund wallets with some native & WETH
        vm.deal(safe, 1000 ether);
        vm.deal(user, payment * 10);
        vm.startPrank(user);
        weth.deposit{value: payment * 2}();
        weth.approve(address(ff), type(uint256).max);
        vm.stopPrank();

        // transfer ownership of StakingMgr to Fee Flow contract to be able to set up rewards
        vm.prank(safe);
        pos.transferOwnership(address(ff));
    }

    function assetsAddresses() public view returns (address[] memory addresses) {
        addresses = new address[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            addresses[i] = address(tokens[i]);
        }
        return addresses;
    }

    function test_BuyNative_WhenContractHasNative() public {
        // Fund contract with native tokens
        uint256 initialNative = 10_000 ether;
        vm.deal(address(ff), initialNative);

        uint256 epochId = ff.getSlot0().epochId;
        uint256 deadline = block.timestamp + 1 hours;

        uint256 userBalanceBefore = user.balance;
        uint256 contractBalanceBefore = address(ff).balance;
        uint256 posWethBefore = weth.balanceOf(address(pos));
        assertEq(
            contractBalanceBefore, initialNative, "Contract should have initial native balance"
        );

        vm.prank(user);
        ff.buyNative{value: payment}(assetsAddresses(), user, epochId, deadline);

        uint256 userBalanceAfter = user.balance;
        uint256 contractBalanceAfter = address(ff).balance;
        uint256 posWethAfter = weth.balanceOf(address(pos));

        assertEq(userBalanceAfter, userBalanceBefore - payment, "User should spend native");
        assertEq(
            contractBalanceAfter, 0, "Contract native should be wrapped and registered as rewards"
        );
        assertEq(
            posWethAfter,
            posWethBefore + payment + initialNative,
            "StakingManager WETH balance should increase by payment- & wrapped amount"
        );
        assertEq(token1.balanceOf(user), tokenAmount, "User should receive token1");
        assertEq(token2.balanceOf(user), tokenAmount * 2, "User should receive token2");
    }

    function test_BuyNative_WhenContractHasNoNative() public {
        uint256 epochId = ff.getSlot0().epochId;
        uint256 deadline = block.timestamp + 1 hours;

        uint256 userBalanceBefore = user.balance;
        uint256 contractBalanceBefore = address(ff).balance;
        uint256 posWethBefore = weth.balanceOf(address(pos));
        assertEq(contractBalanceBefore, 0, "Contract should have NO initial native balance");

        vm.prank(user);
        ff.buyNative{value: payment}(assetsAddresses(), user, epochId, deadline);

        uint256 userBalanceAfter = user.balance;
        uint256 contractBalanceAfter = address(ff).balance;
        uint256 posWethAfter = weth.balanceOf(address(pos));

        assertEq(userBalanceAfter, userBalanceBefore - payment, "User should spend native");
        assertEq(
            contractBalanceAfter, 0, "Payment native should be wrapped and registered as rewards"
        );
        assertEq(
            posWethAfter,
            posWethBefore + payment,
            "StakingManager WETH balance should increase by payment amount"
        );
        assertEq(token1.balanceOf(user), tokenAmount, "User should receive token1");
        assertEq(token2.balanceOf(user), tokenAmount * 2, "User should receive token2");
    }

    function test_Buy_WhenContractHasNative() public {
        // Fund contract with native
        uint256 initialNative = 100 ether;
        vm.deal(address(ff), initialNative);

        uint256 epochId = ff.getSlot0().epochId;
        uint256 deadline = block.timestamp + 1 hours;

        uint256 userWethBefore = weth.balanceOf(user);
        uint256 posWethBefore = weth.balanceOf(address(pos));
        uint256 contractBalanceBefore = address(ff).balance;
        assertEq(
            contractBalanceBefore, initialNative, "Contract should have initial native balance"
        );

        vm.prank(user);
        ff.buy(assetsAddresses(), user, epochId, deadline, payment);

        uint256 userWethAfter = weth.balanceOf(user);
        uint256 contractWethAfter = weth.balanceOf(address(ff));
        uint256 contractBalanceAfter = address(ff).balance;
        uint256 posWethAfter = weth.balanceOf(address(pos));

        assertEq(userWethAfter, userWethBefore - payment, "User should spend WETH");
        assertEq(
            contractBalanceAfter, 0, "Contract native should be wrapped and registered as rewards"
        );
        assertEq(contractWethAfter, 0, "Payment WETH should be wrapped and registered as rewards");
        assertEq(
            posWethAfter,
            posWethBefore + payment + initialNative,
            "StakingManager WETH balance should increase by payment- & wrapped amount"
        );
        assertEq(token1.balanceOf(user), tokenAmount, "User should receive token1");
        assertEq(token2.balanceOf(user), tokenAmount * 2, "User should receive token2");
    }

    function test_Buy_WhenContractHasNoNative() public {
        uint256 epochId = ff.getSlot0().epochId;
        uint256 deadline = block.timestamp + 1 hours;

        uint256 userWethBefore = weth.balanceOf(user);
        uint256 posWethBefore = weth.balanceOf(address(pos));
        uint256 contractBalanceBefore = address(ff).balance;
        assertEq(contractBalanceBefore, 0, "Contract should have NO initial native balance");

        vm.prank(user);
        ff.buy(assetsAddresses(), user, epochId, deadline, payment);

        uint256 userWethAfter = weth.balanceOf(user);
        uint256 contractWethAfter = weth.balanceOf(address(ff));
        uint256 contractBalanceAfter = address(ff).balance;
        uint256 posWethAfter = weth.balanceOf(address(pos));

        assertEq(userWethAfter, userWethBefore - payment, "User should spend WETH");
        assertEq(
            contractBalanceAfter, 0, "Contract native should be wrapped and registered as rewards"
        );
        assertEq(contractWethAfter, 0, "Payment WETH should be wrapped and registered as rewards");
        assertEq(
            posWethAfter,
            posWethBefore + payment,
            "StakingManager WETH balance should increase by payment amount"
        );
        assertEq(token1.balanceOf(user), tokenAmount, "User should receive token1");
        assertEq(token2.balanceOf(user), tokenAmount * 2, "User should receive token2");
    }

    function test_RegisterBlockGasRewards_WhenContractHasNative() public {
        // Fund contract with native
        uint256 initialNative = MIN_REGISTER_BALANCE * 50;
        vm.deal(address(ff), initialNative);

        uint256 contractNativeBefore = address(ff).balance;
        uint256 userWethBefore = weth.balanceOf(user);
        uint256 posWethBefore = weth.balanceOf(address(pos));

        // Call as user
        vm.prank(user);
        uint256 incentive = ff.registerBlockGasRewards();
        assertEq(
            incentive, (contractNativeBefore * INCENTIVE_BIPS) / 10_000, "Incentive should match"
        );
        assertEq(INCENTIVE_BIPS, ff.incentiveBps(), "Incentive bips should match config");

        uint256 contractNativeAfter = address(ff).balance;
        uint256 userWethAfter = weth.balanceOf(user);
        uint256 posWethAfter = weth.balanceOf(address(pos));

        assertEq(contractNativeAfter, 0, "All native should be wrapped");
        assertEq(userWethAfter, userWethBefore + incentive, "User should receive incentive in WETH");
        assertEq(
            posWethAfter,
            posWethBefore + contractNativeBefore - incentive,
            "StakingManager WETH balance should increase by wrapped amount minus incentive"
        );
        assertEq(token1.balanceOf(user), 0, "User should not have any token1");
        assertEq(token2.balanceOf(user), 0, "User should not have any token2");
    }

    function test_RegisterBlockGasRewards_WhenContractHasNotEnoughNative() public {
        // Fund contract with an insufficient amount of native
        uint256 initialNative = MIN_REGISTER_BALANCE / 2;
        vm.deal(address(ff), initialNative);

        uint256 contractNativeBefore = address(ff).balance;
        uint256 contractWethBefore = weth.balanceOf(address(ff));
        uint256 userWethBefore = weth.balanceOf(user);
        uint256 posWethBefore = weth.balanceOf(address(pos));
        assertEq(contractNativeBefore, initialNative, "Contract native balance");

        // Should revert due to NativeBalanceTooLow
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                FeeFlowRewards.NativeBalanceTooLow.selector, contractNativeBefore
            )
        );
        ff.registerBlockGasRewards();

        uint256 contractNativeAfter = address(ff).balance;
        uint256 contractWethAfter = weth.balanceOf(address(ff));
        uint256 userWethAfter = weth.balanceOf(user);
        uint256 posWethAfter = weth.balanceOf(address(pos));

        assertEq(contractNativeAfter, contractNativeBefore, "No change in contract native balance");
        assertEq(contractWethAfter, contractWethBefore, "No change in contract WETH balance");
        assertEq(userWethAfter, userWethBefore, "No change in user WETH balance");
        assertEq(posWethAfter, posWethBefore, "No change in StakingManager WETH balance");
        assertEq(token1.balanceOf(user), 0, "User should not have any token1");
    }
}
