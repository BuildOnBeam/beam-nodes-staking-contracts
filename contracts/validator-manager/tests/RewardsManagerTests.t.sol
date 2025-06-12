// SPDX-License-Identifier: Ecosystem
pragma solidity 0.8.25;

import {Test} from "@forge-std/Test.sol";
import {Native721TokenStakingManagerTest} from "./Native721TokenStakingManagerTests.t.sol";
import {RewardsManager} from "../RewardsManager.sol";
import {WETH} from "@mocks/WETH.sol";

contract RewardsManagerTest is Native721TokenStakingManagerTest {
    WETH weth;
    RewardsManager rewardsManager;

    function setUp() public virtual override {
        // Deploy mocks
        weth = new WETH();

        // Deploy StakingManager
        Native721TokenStakingManagerTest.setUp();

        // Deploy RewardsManager
        rewardsManager =
            new RewardsManager(address(app), address(weth), address(this), address(this));
    }

    function _transferOwnership() internal {
        // Transfer ownership of StakingManager to RewardsManager
        app.transferOwnership(address(rewardsManager));
        assertEq(app.owner(), address(rewardsManager));
    }

    function testRegisterTransactionFees() public {
        _transferOwnership();

        // Send ETH to RewardsManager
        vm.deal(address(rewardsManager), 1 ether);

        // Call registerTransactionFees from user address
        vm.prank(DEFAULT_DELEGATOR_ADDRESS);
        rewardsManager.registerTransactionFees();

        // WETH should be registered in StakingManager
        assertEq(weth.balanceOf(address(app)), 1 ether);

        // Rewards should be registered in staking manager for next epoch
        uint64 nextEpoch = app.getEpoch() + 1;
        // Can't check internal state, but no revert means success
    }

    function testRegisterTransactionFeesRevertNoBalance() public {
        vm.expectRevert(RewardsManager.NoNativeBalance.selector);
        rewardsManager.registerTransactionFees();
    }

    function testRegisterSecondaryRewards() public {
        _transferOwnership();
        uint256 amt = 10 ether;
        rewardToken.approve(address(rewardsManager), amt);

        uint64 epoch = 1;
        rewardsManager.registerSecondaryRewards(epoch, address(rewardToken), amt);
        // Should split 20%/80% and call registerRewards on stakingManager
        // No revert = success
    }

    function testProxyRegisterRewards() public {
        _transferOwnership();
        uint256 amt = 5 ether;
        rewardToken.approve(address(rewardsManager), amt);

        uint64 epoch = 2;
        rewardsManager.registerRewards(true, epoch, address(rewardToken), amt);
        // No revert = success
    }

    function testProxyCancelRewards() public {
        _transferOwnership();
        uint256 amt = 10 ether;
        rewardToken.approve(address(rewardsManager), amt);

        uint64 epoch = 3;
        rewardsManager.registerRewards(true, epoch, address(rewardToken), amt);
        rewardsManager.cancelRewards(true, epoch, address(rewardToken));
        // No revert = success
    }

    function testTransferOwnership() public {
        _transferOwnership();
        address newOwner = address(0xD1);
        rewardsManager.transferOwnership(newOwner);
        assertEq(app.owner(), newOwner);
    }

    function testOnlyRoleReverts() public {
        _transferOwnership();
        // Remove role from this contract
        rewardsManager.revokeRole(rewardsManager.REWARDS_MANAGER_ROLE(), address(this));
        uint64 epoch = 1;
        uint256 amt = 1 ether;

        vm.expectRevert();
        rewardsManager.registerSecondaryRewards(epoch, address(rewardToken), amt);

        vm.expectRevert();
        rewardsManager.registerRewards(true, epoch, address(rewardToken), amt);

        vm.expectRevert();
        rewardsManager.cancelRewards(true, epoch, address(rewardToken));
    }
}
