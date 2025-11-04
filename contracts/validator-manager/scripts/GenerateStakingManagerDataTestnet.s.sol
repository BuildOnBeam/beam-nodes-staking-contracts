// SPDX-License-Identifier: Ecosystem
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {Native721TokenStakingManager} from "../Native721TokenStakingManager.sol";
import {ICMInitializable} from "@utilities/ICMInitializable.sol";
import {console} from "forge-std/console.sol";
import {StakingManagerSettings} from "../Native721TokenStakingManager.sol";
import {ValidatorManager} from "../ValidatorManager.sol";
/**
 * @notice Script to generate call data for upgrading the Native721TokenStakingManager contract (Testnet)
 *
 * @dev To run this script:
 * 1. Make sure to bump reinitializer(n) in Native721TokenStakingManager:initialize in new implementation
 * 2. Run the script with forge:
 *    ```bash
 *    # Generate initialization data
 *    forge script contracts/validator-manager/scripts/GenerateStakingManagerDataTestnet.s.sol --slow --optimize --optimizer-runs 200 -vvv --rpc-url https://build.onbeam.com/rpc/testnet
 *    ```
 * 3. Manually upgrade the proxy using ProxyAdmin, by calling `upgradeAndCall(stakingManagerProxy, newImplementation, generatedData)`
 */

contract GenerateStakingManagerDataTestnet is Script {
    // testnet
    address constant _PROXY_ADDRESS = address(0xF4B5869AabE19a106C0df25E1537d855b54EEcBD);
    address constant _PROXY_ADMIN_ADDRESS = address(0x4CDd1785908756dc515aFc766E3e3A9630761fa1);

    // settings:
    address constant NFT_TOKEN_ADDRESS = address(0x732080D7aD6A9C50039d7Ad7F5BD0a79670f7654);
    address constant ADMIN_ADDRESS = address(0xd68F802fD0B6f56524F379805DD8FcC152DB9d5c);
    address constant VALIDATOR_MANAGER_ADDRESS = address(0x33B9785E20ec582d5009965FB3346F1716e8A423);
    uint64 constant MINIMUM_STAKE_DURATION = 1 hours;
    uint256 constant MINIMUM_STAKE_AMOUNT = 20_000e18;
    uint256 constant MAXIMUM_STAKE_AMOUNT = 200_000_000e18;
    uint64 constant UNLOCK_PERIOD = 1 hours;
    uint16 constant MINIMUM_DELEGATION_FEE = 100; // 0.1% in basis points
    uint64 constant EPOCH_DURATION = 2 days;
    uint256 constant MAXIMUM_NFT_AMOUNT = 1000;
    uint256 constant MINIMUM_DELEGATION_AMOUNT = 100e18;
    uint256 constant WEIGHT_TO_VALUE_FACTOR = 1e18;
    bytes32 constant UPTIME_BLOCKCHAIN_ID =
        bytes32(hex"7f78fe8ca06cefa186ef29c15231e45e1056cd8319ceca0695ca61099e610355");
    uint64 constant EPOCH_OFFSET = 0;
    address constant UPTIME_KEEPER = address(0xd68F802fD0B6f56524F379805DD8FcC152DB9d5c);

    function run() external {
        // Add settings struct for initialization
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

        // use if settings change and contract needs to be re-initialized
        bytes memory initSelector = abi.encodeWithSelector(
            Native721TokenStakingManager.initialize.selector, settings, address(NFT_TOKEN_ADDRESS)
        );

        string memory initData = vm.toString(initSelector);

        console.log("StakingManager Proxy address:", _PROXY_ADDRESS);
        console.log("ProxyAdmin address:", _PROXY_ADMIN_ADDRESS);
        console.log(
            "\nInitialization data for ProxyAdmin upgrade call `upgradeAndCall(proxy, implementation, data)`, with data = ",
            initData
        );
    }
}
