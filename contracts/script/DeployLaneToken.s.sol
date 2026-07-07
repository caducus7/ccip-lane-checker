// SPDX-License-Identifier: LicenseRef-Caducus-Commercial
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {LaneToken} from "../src/core/LaneToken.sol";
import {ChainConfig} from "../src/libraries/ChainConfig.sol";

/// @title DeployLaneToken
/// @notice Deploys the solo-mode LaneToken on a testnet from ChainConfig.
/// @dev Example:
///        DEPLOY_CHAIN=sepolia VRF_SUBSCRIPTION_ID=<uint256 sub id> \
///        forge script script/DeployLaneToken.s.sol:DeployLaneToken --rpc-url $SEPOLIA_RPC --broadcast
contract DeployLaneToken is Script {
    function run() external returns (LaneToken laneToken) {
        uint256 deployKey = vm.envUint("PRIVATE_KEY");
        string memory chainName = vm.envOr("DEPLOY_CHAIN", string("sepolia"));
        ChainConfig.Network network = ChainConfig.networkFromEnv(chainName);
        ChainConfig.NetworkConfig memory cfg = ChainConfig.getNetworkConfig(network);

        // VRF v2.5 subscription IDs are full uint256 values.
        uint256 vrfSubId = vm.envUint("VRF_SUBSCRIPTION_ID");
        uint256[] memory supportedChains = ChainConfig.supportedChainSelectors();

        vm.startBroadcast(deployKey);
        laneToken = new LaneToken(
            cfg.ccipRouter,
            cfg.linkToken,
            cfg.vrfCoordinator,
            vrfSubId,
            cfg.vrfKeyHash,
            cfg.chainId,
            cfg.chainSelector,
            supportedChains
        );
        vm.stopBroadcast();

        console2.log("Chain:", cfg.name);
        console2.log("LaneToken:", address(laneToken));
        console2.log("Remember: add LaneToken as a VRF v2.5 consumer and fund the subscription.");
    }
}
