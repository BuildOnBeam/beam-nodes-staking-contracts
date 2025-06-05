// SPDX-License-Identifier: AGPL-3.0-or-later
// (c) 2025, Beam Labs

pragma solidity 0.8.25;

import {IRewardsManager} from "./interfaces/IRewardsManager.sol";
import {INative721TokenStakingManager} from "./interfaces/INative721TokenStakingManager.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {IOwnable} from "./interfaces/IOwnable.sol";
import {IERC20} from "@openzeppelin/contracts@5.0.2/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts@5.0.2/utils/ReentrancyGuard.sol";
import {AccessControlEnumerable} from
    "@openzeppelin/contracts@5.0.2/access/extensions/AccessControlEnumerable.sol";

/**
 * Contract to collect and set up native primary rewards permissionlessly.
 * Additionally acts as a permissioned proxy for general rewards setup.
 */
contract RewardsManager is IRewardsManager, AccessControlEnumerable, ReentrancyGuard {
    bytes32 public constant REWARDS_MANAGER_ROLE = keccak256("REWARDS_MANAGER_ROLE");
    address public weth;
    address public stakingManager;

    error NoNativeBalance();
    error ERC20ApprovalFailed();

    constructor(address stakingManager_, address weth_, address admin, address rewardManager) {
        stakingManager = stakingManager_;
        weth = weth_;
        grantRole(DEFAULT_ADMIN_ROLE, admin);
        grantRole(REWARDS_MANAGER_ROLE, rewardManager);
    }

    /**
     * @notice See {IRewardsManager-registerTransactionFees}.
     */
    function registerTransactionFees() external virtual nonReentrant {
        uint256 nativeBalance = address(this).balance;

        // revert if contract has no native balance
        if (nativeBalance == 0) {
            revert NoNativeBalance();
        }

        // wrap native tokens locked in contract
        IWETH(weth).deposit{value: nativeBalance}();

        // approve WETH to staking manager
        if (!IERC20(weth).approve(stakingManager, nativeBalance)) {
            revert ERC20ApprovalFailed();
        }

        // get *next* epoch
        INative721TokenStakingManager _stakingManager =
            INative721TokenStakingManager(stakingManager);
        uint64 nextEpoch = _stakingManager.getEpoch() + 1;

        // register primary rewards for next epoch
        _stakingManager.registerRewards(true, nextEpoch, weth, nativeBalance);
    }

    /**
     * @notice See {IRewardsManager-registerSecondaryRewards}.
     */
    function registerSecondaryRewards(
        uint64 epoch,
        address token,
        uint256 amount
    ) external virtual onlyRole(REWARDS_MANAGER_ROLE) nonReentrant {
        // calculate rewards pool distribution
        uint256 primaryAmount = amount / 5; // 20% of the amount goes to BEAM staking rewards
        uint256 secondaryAmount = amount - primaryAmount; // 80% of the amount goes to NFT rewards

        // register rewards
        INative721TokenStakingManager(stakingManager).registerRewards(
            true, epoch, token, primaryAmount
        );
        INative721TokenStakingManager(stakingManager).registerRewards(
            false, epoch, token, secondaryAmount
        );
    }

    /**
     * @notice See {IRewardsManager-registerRewards}.
     */
    function registerRewards(
        bool primary,
        uint64 epoch,
        address token,
        uint256 amount
    ) external virtual onlyRole(REWARDS_MANAGER_ROLE) nonReentrant {
        INative721TokenStakingManager(stakingManager).registerRewards(primary, epoch, token, amount);
    }

    /**
     * @notice See {IRewardsManager-cancelRewards}.
     */
    function cancelRewards(
        bool primary,
        uint64 epoch,
        address token
    ) external onlyRole(REWARDS_MANAGER_ROLE) nonReentrant {
        INative721TokenStakingManager(stakingManager).cancelRewards(primary, epoch, token);
    }

    /**
     * @dev See {IRewardsManager-transferOwnership}.
     */
    function transferOwnership(
        address newOwner
    ) external virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        IOwnable(stakingManager).transferOwnership(newOwner);
    }
}
