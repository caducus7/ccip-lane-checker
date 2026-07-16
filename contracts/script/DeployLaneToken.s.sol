// SPDX-License-Identifier: LicenseRef-Caducus-Commercial
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {BroadcastScript} from "./BroadcastScript.sol";
import {LaneToken} from "../src/core/LaneToken.sol";
import {ChainConfig} from "../src/libraries/ChainConfig.sol";

/// @title DeployLaneToken
/// @notice Deploys the solo-mode LaneToken on a testnet from ChainConfig.
/// @dev Example (keystore):
///        export DEPLOYER=$(cast wallet address --account laneDeployer)
///        DEPLOY_CHAIN=sepolia VRF_SUBSCRIPTION_ID=<uint256 sub id> \
///        forge script script/DeployLaneToken.s.sol:DeployLaneToken \
///          --rpc-url $SEPOLIA_RPC --account laneDeployer --sender $DEPLOYER --broadcast
contract DeployLaneToken is BroadcastScript {
    function run() external returns (LaneToken laneToken) {
        string memory chainName = vm.envOr("DEPLOY_CHAIN", string("sepolia"));
        ChainConfig.Network network = ChainConfig.networkFromEnv(chainName);
        ChainConfig.NetworkConfig memory cfg = ChainConfig.getNetworkConfig(network);

        uint256 vrfSubId = vm.envUint("VRF_SUBSCRIPTION_ID");
        uint256[] memory supportedChains = ChainConfig.supportedChainSelectors();

        _startDeployBroadcast();
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
