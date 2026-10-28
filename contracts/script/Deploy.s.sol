// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {GuardianModule} from "../src/GuardianModule.sol";
import {RecoveryModule} from "../src/RecoveryModule.sol";
import {SpendModule} from "../src/SpendModule.sol";

/// Deploys the three validator modules (spend, guardian, recovery). Run
/// against the local Anvil Base-fork simulator with:
///   forge script script/Deploy.s.sol --rpc-url local --broadcast
contract Deploy is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerKey);

        SpendModule spendModule = new SpendModule();
        console.log("SpendModule deployed at", address(spendModule));

        GuardianModule guardianModule = new GuardianModule();
        console.log("GuardianModule deployed at", address(guardianModule));

        RecoveryModule recoveryModule = new RecoveryModule();
        console.log("RecoveryModule deployed at", address(recoveryModule));

        vm.stopBroadcast();
    }
}
