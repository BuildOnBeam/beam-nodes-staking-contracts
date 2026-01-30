// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {
    GovernorUpgradeable
} from "@openzeppelin/contracts-upgradeable@5.0.2/governance/GovernorUpgradeable.sol";
import {
    GovernorCountingSimpleUpgradeable
} from "@openzeppelin/contracts-upgradeable@5.0.2/governance/extensions/GovernorCountingSimpleUpgradeable.sol";
import {
    GovernorSettingsUpgradeable
} from "@openzeppelin/contracts-upgradeable@5.0.2/governance/extensions/GovernorSettingsUpgradeable.sol";
import {
    GovernorStorageUpgradeable
} from "@openzeppelin/contracts-upgradeable@5.0.2/governance/extensions/GovernorStorageUpgradeable.sol";
import {
    GovernorVotesUpgradeable
} from "@openzeppelin/contracts-upgradeable@5.0.2/governance/extensions/GovernorVotesUpgradeable.sol";
import {
    GovernorVotesQuorumFractionUpgradeable
} from "@openzeppelin/contracts-upgradeable@5.0.2/governance/extensions/GovernorVotesQuorumFractionUpgradeable.sol";
import {IVotes} from "@openzeppelin/contracts@5.0.2/governance/utils/IVotes.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts@5.0.2/proxy/utils/UUPSUpgradeable.sol";

contract StakingGovernor is
    GovernorUpgradeable,
    GovernorSettingsUpgradeable,
    GovernorCountingSimpleUpgradeable,
    GovernorStorageUpgradeable,
    GovernorVotesUpgradeable,
    GovernorVotesQuorumFractionUpgradeable,
    UUPSUpgradeable
{
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev Initializes the governor contract.
    function initialize(
        IVotes _vote
    ) public initializer {
        __Governor_init("StakingGovernor");
        __GovernorSettings_init(1 days, 2 weeks, 25_000_000); // voting delay, voting period, min votes to propose
        __GovernorCountingSimple_init();
        __GovernorStorage_init();
        __GovernorVotes_init(_vote); // contract that tracks voting power (i.e. ValidatorManager)
        __GovernorVotesQuorumFraction_init(51); // quorum in %
    }

    /// @dev Restricts governor upgrade access to governance.
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyGovernance {}

    // The following functions are overrides required by Solidity.

    function proposalThreshold()
        public
        view
        override (GovernorUpgradeable, GovernorSettingsUpgradeable)
        returns (uint256)
    {
        return super.proposalThreshold();
    }

    function _propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description,
        address proposer
    ) internal override (GovernorUpgradeable, GovernorStorageUpgradeable) returns (uint256) {
        return super._propose(targets, values, calldatas, description, proposer);
    }
}
