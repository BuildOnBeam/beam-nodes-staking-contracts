// (c) 2024, Ava Labs, Inc. All rights reserved.
// See the file LICENSE for licensing terms.

// SPDX-License-Identifier: Ecosystem

// run via `forge test -vvvv --match-path "contracts/validator-manager/tests/ForkUpgradeStakingManagerTestnet.t.sol" 2>&1`

pragma solidity 0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {ProxyAdmin} from "@openzeppelin/contracts@5.0.2/proxy/transparent/ProxyAdmin.sol";
import {
    ITransparentUpgradeableProxy
} from "@openzeppelin/contracts@5.0.2/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Native721TokenStakingManagerV2} from "../Native721TokenStakingManagerV2.sol";
import {StakingManagerSettings} from "../interfaces/IStakingManager.sol";
import {ValidatorManager} from "../ValidatorManager.sol";
import {IERC721} from "@openzeppelin/contracts@5.0.2/token/ERC721/IERC721.sol";
import {ICMInitializable} from "@utilities/ICMInitializable.sol";

/**
 * @notice Fork test to reproduce/debug a failing `upgradeAndCall` (with settings re-initialization)
 * against the live Native721TokenStakingManager proxy on Beam testnet.
 *
 * @dev Requires network access to the Beam testnet RPC.
 */
contract ForkUpgradeStakingManagerTestnetTest is Test {
    string constant BEAM_TESTNET_RPC = "https://build.onbeam.com/rpc/testnet";

    // Same addresses/settings as GenerateStakingManagerDataTestnet.s.sol
    address constant PROXY_ADDRESS = 0xF4B5869AabE19a106C0df25E1537d855b54EEcBD;
    address constant PROXY_ADMIN_ADDRESS = 0x4CDd1785908756dc515aFc766E3e3A9630761fa1;

    address constant NFT_TOKEN_ADDRESS = 0x732080D7aD6A9C50039d7Ad7F5BD0a79670f7654;
    address constant ADMIN_ADDRESS = 0xd68F802fD0B6f56524F379805DD8FcC152DB9d5c;
    address constant VALIDATOR_MANAGER_ADDRESS = 0x33B9785E20ec582d5009965FB3346F1716e8A423;
    uint64 constant MINIMUM_STAKE_DURATION = 1 hours;
    uint256 constant MINIMUM_STAKE_AMOUNT = 50_000e18;
    uint256 constant MAXIMUM_STAKE_AMOUNT = 200_000_000e18;
    uint64 constant UNLOCK_PERIOD = 30 minutes;
    uint16 constant MINIMUM_DELEGATION_FEE = 100;
    uint64 constant EPOCH_DURATION = 2 days;
    uint256 constant MAXIMUM_NFT_AMOUNT = 1000;
    uint256 constant MINIMUM_DELEGATION_AMOUNT = 100e18;
    uint256 constant WEIGHT_TO_VALUE_FACTOR = 1e18;
    bytes32 constant UPTIME_BLOCKCHAIN_ID =
        bytes32(hex"7f78fe8ca06cefa186ef29c15231e45e1056cd8319ceca0695ca61099e610355");
    uint64 constant EPOCH_OFFSET = 0;
    address constant UPTIME_KEEPER = 0xd68F802fD0B6f56524F379805DD8FcC152DB9d5c;
    address constant ADDITIONAL_REWARDS_REGISTRAR_ADDRESS =
        0xb25DeeFfBedd8a7149d634AEEc864C9a6Beb61c9;

    // OZ Initializable's ERC-7201 storage slot: keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.Initializable")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 constant INITIALIZABLE_STORAGE =
        0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00;

    ProxyAdmin proxyAdmin;

    function setUp() public {
        vm.createSelectFork(BEAM_TESTNET_RPC);
        proxyAdmin = ProxyAdmin(PROXY_ADMIN_ADDRESS);
    }

    function testUpgradeAndCallWithSettings() public {
        // Log the currently stored `_initialized` version before upgrading, since
        // `reinitializer(n)` reverts with `InvalidInitialization` if `n` was already used.
        uint64 initializedBefore = uint64(uint256(vm.load(PROXY_ADDRESS, INITIALIZABLE_STORAGE)));
        console.log("Current _initialized version:", initializedBefore);

        Native721TokenStakingManagerV2 newImplementation =
            new Native721TokenStakingManagerV2(ICMInitializable.Disallowed);
        console.log("Deployed new implementation at:", address(newImplementation));

        StakingManagerSettings memory settings = StakingManagerSettings({
            manager: ValidatorManager(VALIDATOR_MANAGER_ADDRESS),
            minimumStakeAmount: MINIMUM_STAKE_AMOUNT,
            maximumStakeAmount: MAXIMUM_STAKE_AMOUNT,
            maximumNFTAmount: MAXIMUM_NFT_AMOUNT,
            minimumStakeDuration: MINIMUM_STAKE_DURATION,
            minimumDelegationAmount: MINIMUM_DELEGATION_AMOUNT,
            minimumDelegationFeeBips: MINIMUM_DELEGATION_FEE,
            weightToValueFactor: WEIGHT_TO_VALUE_FACTOR,
            admin: ADMIN_ADDRESS,
            uptimeBlockchainID: UPTIME_BLOCKCHAIN_ID,
            epochDuration: EPOCH_DURATION,
            unlockDuration: UNLOCK_PERIOD,
            uptimeKeeper: UPTIME_KEEPER,
            epochOffset: EPOCH_OFFSET
        });

        bytes memory initData = abi.encodeWithSelector(
            Native721TokenStakingManagerV2.initialize.selector,
            settings,
            IERC721(NFT_TOKEN_ADDRESS),
            ADDITIONAL_REWARDS_REGISTRAR_ADDRESS
        );

        address admin = proxyAdmin.owner();

        // Use a raw call so a revert reason (custom error/string) can be decoded and logged,
        // instead of the whole test aborting on revert.
        vm.prank(admin);
        (bool success, bytes memory returnData) = address(proxyAdmin)
            .call(
                abi.encodeWithSelector(
                    ProxyAdmin.upgradeAndCall.selector,
                    ITransparentUpgradeableProxy(PROXY_ADDRESS),
                    address(newImplementation),
                    initData
                )
            );

        if (!success) {
            console.log("upgradeAndCall reverted, raw returndata:");
            console.logBytes(returnData);
            revert("upgradeAndCall failed - see logged returndata above for the revert reason");
        }

        // Sanity-check the new settings were actually applied.
        Native721TokenStakingManagerV2 app = Native721TokenStakingManagerV2(payable(PROXY_ADDRESS));
        assertEq(address(app.erc721()), NFT_TOKEN_ADDRESS, "erc721 token not updated");
    }
}
