// SPDX-License-Identifier: AGPL-3.0-or-later
// (c) 2025, Beam Labs

pragma solidity 0.8.25;

/**
 * Contract to collect and set up native primary rewards permissionlessly.
 * Additionally acts as a permissioned proxy for `Native721TokenStakingManager` for secondary rewards setup.
 */
interface IRewardsManager {
    /**
     * @notice Wraps the native tokens held by the contract, and registers them as primary staking rewards for the next epoch with the managed staking contract.
     */
    function registerTransactionFees() external;

    /**
     * @notice Registers a secondary reward amount for a specific epoch and token.
     * @dev Splits the provided amount of tokens into 20% primary (BEAM staking-) and 80% secondary (NFT staking-) rewards.
     * @param epoch The staking epoch for which rewards are being registered.
     * @param token The address of the token being allocated as a reward.
     * @param amount The amount of the token to be distributed as rewards.
     */
    function registerSecondaryRewards(uint64 epoch, address token, uint256 amount) external;

    /**
     * @notice Shorthand to register secondary rewards for the *next* epoch.
     */
    function registerNextSecondaryRewards(address token, uint256 amount) external;

    /**
     * @notice Registers a reward amount for a specific epoch and token.
     * @dev This function acts as a permissioned proxy for {INative721TokenStakingManager-registerRewards}.
     * @param primary A boolean indicating whether to register in the primary reward pool (true) or the NFT pool (false).
     * @param epoch The staking epoch for which rewards are being registered.
     * @param token The address of the token being allocated as a reward.
     * @param amount The amount of the token to be distributed as rewards.
     */
    function registerRewards(bool primary, uint64 epoch, address token, uint256 amount) external;

    /**
     * @notice Cancels previously registered rewards before the claim period starts.
     * @dev This function acts as a permissioned proxy for {INative721TokenStakingManager-cancelRewards}.
     * @param primary A boolean indicating whether to cancel from the primary reward pool (true) or the NFT pool (false).
     * @param epoch The staking epoch for which rewards should be canceled.
     * @param token The address of the token whose rewards should be canceled.
     */
    function cancelRewards(bool primary, uint64 epoch, address token) external;

    /**
     * @notice Transfers ownership of the managed staking contract.
     * @dev This function is proxy for {IOwnable-transferOwnership} to transfer ownership of the managed staking contract to a new owner.
     * @param newOwner The address of the new owner.
     *
     * Requirements:
     * - Can only be called by an admin.
     */
    function transferOwnership(
        address newOwner
    ) external;
}
