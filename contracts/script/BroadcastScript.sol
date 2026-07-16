// SPDX-License-Identifier: LicenseRef-Caducus-Commercial
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";

/// @title BroadcastScript
/// @notice Shared deploy broadcast helper for keystore or PRIVATE_KEY workflows.
/// @dev Keystore: export DEPLOYER=$(cast wallet address --account laneDeployer)
///      forge script ... --account laneDeployer --sender $DEPLOYER --broadcast
abstract contract BroadcastScript is Script {
    function _startDeployBroadcast() internal returns (address deployer) {
        if (vm.envExists("PRIVATE_KEY")) {
            uint256 deployKey = vm.envUint("PRIVATE_KEY");
            deployer = vm.addr(deployKey);
            vm.startBroadcast(deployKey);
        } else {
            deployer = vm.envAddress("DEPLOYER");
            vm.startBroadcast(deployer);
        }
    }
}
