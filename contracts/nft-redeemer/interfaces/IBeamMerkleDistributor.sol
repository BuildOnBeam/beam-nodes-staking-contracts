// SPDX-License-Identifier: GPL-3.0-or-later
// adapted from: https://github.com/Uniswap/merkle-distributor
pragma solidity ^0.8.20;

// Allows anyone to claim a token if they exist in a merkle root.
interface IBeamMerkleDistributor {
    error AlreadyClaimed();
    error InvalidProof();
    error ClaimWindowFinished();
    error NoBalanceToWithdraw();

    // Returns the address of the token distributed by this contract.
    function token() external view returns (address);
    // Returns the merkle root of the merkle tree containing account balances available to claim.
    function merkleRoot() external view returns (bytes32);
    // Returns true if the account has been marked claimed.
    function isClaimed(
        address account
    ) external view returns (bool);
    // Claim the given amount of the token to the given address. Reverts if the inputs are invalid.
    function claim(
        address account,
        uint256 amount,
        bytes32[] calldata merkleProof
    ) external;

    // recovers any ERC20 tokens sent to the contract (owner only)
    function withdraw(
        address token_
    ) external;

    // This event is triggered whenever a call to #claim succeeds.
    event Claimed(address account, uint256 amount);

    // This event is triggered whenever a call to #withdraw succeeds.
    event Withdrawn(address indexed token, uint256 amount, address indexed to);
}
