// SPDX-License-Identifier: Ecosystem
pragma solidity 0.8.25;

import {ICMInitializable} from "@utilities/ICMInitializable.sol";
import {Script} from "forge-std/Script.sol";
import {ValidatorManagerSettings, ValidatorManager} from "../ValidatorManager.sol";
import {console} from "forge-std/console.sol";

/**
 * @notice Script to generate call data for upgrading the ValidatorManager contract (Testnet)
 *
 * @dev To run this script:
 * 1. Make sure to bump reinitializer(n) in ValidatorManager:initialize in new implementation
 * 2. Run the script with forge:
 *    ```bash
 *    # Generate initialization data
 *    forge script contracts/validator-manager/scripts/GenerateValidatorManagerDataTestnet.s.sol --slow --optimize --optimizer-runs 200 -vvv --rpc-url https://build.onbeam.com/rpc/testnet
 *    ```
 * 3. Manually upgrade the proxy using ProxyAdmin, by calling `upgradeAndCall(validatorManagerProxy, newImplementation, generatedData)`
 */
contract GenerateValidatorManagerDataTestnet is Script {
    // testnet
    address private constant _PROXY_ADDRESS = address(0x33B9785E20ec582d5009965FB3346F1716e8A423);

    // settings:
    address private constant _ADMIN_ADDRESS = address(0xF4B5869AabE19a106C0df25E1537d855b54EEcBD); // = StakingManager contract address
    bytes32 private constant _SUBNET_ID =
        bytes32(hex"5e8b6e2e8155e93739f2fa6a7f8a32c6bb2e1dce2e471b56dcc60aac49bf3435"); // convert your SubnetID to hex using avatools.io
    uint64 private constant _CHURN_PERIOD = 1 hours;
    uint8 private constant _MAX_CHURN_PERCENTAGE = 20;

    function run() external {
        // Prepare initialization data
        ValidatorManagerSettings memory settings = ValidatorManagerSettings({
            admin: _ADMIN_ADDRESS,
            subnetID: _SUBNET_ID,
            churnPeriodSeconds: _CHURN_PERIOD,
            maximumChurnPercentage: _MAX_CHURN_PERCENTAGE
        });

        // Encode the initialization call
        bytes memory initSelector =
            abi.encodeWithSelector(ValidatorManager.initialize.selector, settings);

        // Get ProxyAdmin interface from proxy
        bytes32 adminSlot = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
        address proxyAdmin = address(uint160(uint256(vm.load(address(_PROXY_ADDRESS), adminSlot))));

        string memory initData = vm.toString(initSelector);

        console.log("ValidatorManager Proxy address:", _PROXY_ADDRESS);
        console.log("ProxyAdmin address:", proxyAdmin);
        console.log(
            "\nInitialization data for ProxyAdmin upgrade call: `upgradeAndCall(proxy, implementation, data)`, with data = ",
            initData
        );
    }
}
