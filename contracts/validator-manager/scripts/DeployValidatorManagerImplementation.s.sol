// SPDX-License-Identifier: Ecosystem
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {ValidatorManager} from "../ValidatorManager.sol";
import {ICMInitializable} from "@utilities/ICMInitializable.sol";
import {console} from "forge-std/console.sol";

/**
 * @notice Script to deploy a new implementation for the ValidatorManager contract (to be used with Safe).
 *
 * @dev To run this script:
 * 1. Load private keys from .env
 *    ```bash
 *      source .env;set +a;
 *    ```
 * 2. Run the script with forge (update the RPC URL and PK as needed):
 *    ```bash
 *    # Dry run (simulation)
 *    forge script contracts/validator-manager/scripts/DeployValidatorManagerImplementation.s.sol --rpc-url https://build.onbeam.com/rpc/testnet --slow --optimize --optimizer-runs 200 -vv --private-key $PK_TESTNET
 *
 *    # Live run
 *    forge script contracts/validator-manager/scripts/DeployValidatorManagerImplementation.s.sol --rpc-url https://build.onbeam.com/rpc/testnet --slow --optimize --optimizer-runs 200 -vv --private-key $PK_TESTNET --broadcast --verify --verifier sourcify
 *    ```
 * 3. Manually upgrade the proxy using ProxyAdmin, by calling:
 *    - `upgradeAndCall(validatorManagerProxy, newImplementation, 0x)` if settings didn't change.
 *    - use script `GenerateValidatorManagerData(Testnet).s.sol` to generate initialization data if settings have changed.
 *      - (!! Make sure to bump reinitializer(n) in ValidatorManager:initialize in new implementation before deploying).
 */
contract DeployValidatorManagerImplementation is Script {
    function run() external {
        vm.startBroadcast();

        ValidatorManager newImplementation = new ValidatorManager(ICMInitializable.Disallowed);
        console.log("New ValidatorManager implementation deployed at:", address(newImplementation));

        vm.stopBroadcast();

        console.log(
            " - To upgrade without changing settings, call ProxyAdmin: upgradeAndCall(proxy, implementation, 0x)"
        );
        console.log(
            " - Use `GenerateValidatorManagerData[Testnet].s.sol` to generate initialization data if settings have changed"
        );
    }
}
