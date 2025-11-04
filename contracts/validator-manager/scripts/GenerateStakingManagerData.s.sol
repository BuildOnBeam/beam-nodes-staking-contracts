// SPDX-License-Identifier: Ecosystem
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {Native721TokenStakingManager} from "../Native721TokenStakingManager.sol";
import {ICMInitializable} from "@utilities/ICMInitializable.sol";
import {console} from "forge-std/console.sol";
import {StakingManagerSettings} from "../Native721TokenStakingManager.sol";
import {ValidatorManager} from "../ValidatorManager.sol";
/**
 * @notice Script to generate call data for upgrading the Native721TokenStakingManager contract
 *
 * @dev To run this script:
 * 1. Make sure to bump reinitializer(n) in Native721TokenStakingManager:initialize in new implementation
 * 2. Run the script with forge:
 *    ```bash
 *    # Generate initialization data
 *    forge script contracts/validator-manager/scripts/GenerateStakingManagerData.s.sol --slow --optimize --optimizer-runs 200 -vvv --rpc-url https://build.onbeam.com/rpc
 *    ```
 * 3. Manually upgrade the proxy using ProxyAdmin, by calling `upgradeAndCall(stakingManagerProxy, newImplementation, generatedData)`
 */

contract GenerateStakingManagerData is Script {
    // mainnet
    address constant _PROXY_ADDRESS = address(0x2FD428A5484d113294b44E69Cb9f269abC1d5B54);
    address constant _PROXY_ADMIN_ADDRESS = address(0x779F6FFAaeaB220fe43d28D954b4f652EB1dae5d);

    // settings:
    address constant NFT_TOKEN_ADDRESS = address(0x2CB343FAD3a2221824E9E4137b636C31300A8BF0);
    address constant ADMIN_ADDRESS = address(0x277280e8337E64a3A8E8b795D4E8E5e00BF6e203);
    address constant VALIDATOR_MANAGER_ADDRESS = address(0x46d5a1B62095cE9497C6Cc7Ab1BDb8a09D7e3c36);
    uint64 constant MINIMUM_STAKE_DURATION = 1 hours;
    uint256 constant MINIMUM_STAKE_AMOUNT = 20_000e18;
    uint256 constant MAXIMUM_STAKE_AMOUNT = 200_000_000e18;
    uint64 constant UNLOCK_PERIOD = 21 days;
    uint16 constant MINIMUM_DELEGATION_FEE = 100; // 1% in basis points
    uint64 constant EPOCH_DURATION = 2629746; // 31556952/12 (gregorian calendar seconds / 12)
    uint256 constant MAXIMUM_NFT_AMOUNT = 1000;
    uint256 constant MINIMUM_DELEGATION_AMOUNT = 100e18;
    uint256 constant WEIGHT_TO_VALUE_FACTOR = 1e18;
    bytes32 constant UPTIME_BLOCKCHAIN_ID =
        bytes32(hex"f94107902c8418dfcdf51d3f95429688abc7109e0f5b0e806c7e204d542e0761");
    uint64 constant EPOCH_OFFSET = 55998;
    address constant UPTIME_KEEPER = address(0xfEFFD4f8b89111CD085B80Ce994aB34C7e001a69);

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
