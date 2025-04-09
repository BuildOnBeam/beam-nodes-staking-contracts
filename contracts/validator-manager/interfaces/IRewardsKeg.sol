// SPDX-License-Identifier: AGPL-3.0-or-later
// (c) 2025, Beam Labs

pragma solidity 0.8.25;

/**
 * Contract to collect and set up native primary rewards permissionlessly.
 * Additionally acts as a permissioned proxy for `Native721TokenStakingManager` for secondary rewards setup.
 */
interface IRewardsKeg {
    /**
     * @notice Wraps the native tokens held by the contract, and registers them as primary staking rewards for the next epoch.
     */
    function tapPrimaryRewards() external;

    /**
     * @notice Registers a reward amount for a specific epoch and token.
     * @dev This function acts as a permissioned proxy for {INative721TokenStakingManager-registerRewards}
     * @param primary A boolean indicating whether to register in the primary reward pool (true) or the NFT pool (false).
     * @param epoch The staking epoch for which rewards are being registered.
     * @param token The address of the token being allocated as a reward.
     * @param amount The amount of the token to be distributed as rewards.
     */
    function registerRewards(
        bool primary,
        uint64 epoch,
        address token,
        uint256 amount
    ) external;
}
