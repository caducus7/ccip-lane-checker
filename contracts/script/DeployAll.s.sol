// SPDX-License-Identifier: LicenseRef-Caducus-Commercial
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {LaneToken} from "../src/core/LaneToken.sol";
import {LaneController} from "../src/core/LaneController.sol";
import {LaneExecutor} from "../src/core/LaneExecutor.sol";
import {ChainConfig} from "../src/libraries/ChainConfig.sol";

/// @title DeployAll
/// @notice Multi-chain testnet deployment orchestrator for CCIP Lane Checker.
/// @dev Run once per chain with `--rpc-url` and `DEPLOY_CHAIN` set.
///      Example:
///        DEPLOY_CHAIN=sepolia VRF_SUBSCRIPTION_ID=123 PLATFORM_TREASURY=0x... GAS_RESERVE=0x... \
///        forge script script/DeployAll.s.sol:DeployAll --rpc-url $SEPOLIA_RPC --broadcast
contract DeployAll is Script {
    struct DeploymentResult {
        address laneToken;
        address laneController;
        address laneExecutor;
    }

    function run() external returns (DeploymentResult memory result) {
        uint256 deployKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployKey);
        string memory chainName = vm.envOr("DEPLOY_CHAIN", string("sepolia"));
        ChainConfig.Network network = ChainConfig.networkFromEnv(chainName);
        ChainConfig.NetworkConfig memory cfg = ChainConfig.getNetworkConfig(network);

        console2.log("Deploying on:", cfg.name);
        console2.log("Chain ID:", cfg.chainId);
        console2.log("CCIP selector:", cfg.chainSelector);

        vm.startBroadcast(deployKey);

        result.laneToken = _deployLaneToken(cfg);
        result.laneController = _deployLaneController(cfg, deployer);
        result.laneExecutor = _deployLaneExecutor(cfg, deployer, result.laneController);

        vm.stopBroadcast();

        _logSummary(cfg.name, result);
    }

    function _deployLaneToken(ChainConfig.NetworkConfig memory cfg) internal returns (address) {
        // VRF v2.5 subscription IDs are full uint256 values.
        uint256 vrfSubId = vm.envUint("VRF_SUBSCRIPTION_ID");
        uint256[] memory supportedChains = ChainConfig.supportedChainSelectors();

        LaneToken token = new LaneToken(
            cfg.ccipRouter,
            cfg.linkToken,
            cfg.vrfCoordinator,
            vrfSubId,
            cfg.vrfKeyHash,
            supportedChains
        );

        console2.log("LaneToken deployed:", address(token));
        return address(token);
    }

    function _deployLaneController(ChainConfig.NetworkConfig memory cfg, address deployer)
        internal
        returns (address)
    {
        address treasury = vm.envOr("PLATFORM_TREASURY", deployer);
        address gasReserve = vm.envOr("GAS_RESERVE", deployer);
        address creForwarder = vm.envOr("CRE_FORWARDER", deployer);

        LaneController controller = new LaneController(deployer, cfg.linkToken, treasury, gasReserve, creForwarder);

        console2.log("LaneController deployed:", address(controller));
        return address(controller);
    }

    function _deployLaneExecutor(ChainConfig.NetworkConfig memory cfg, address deployer, address controller)
        internal
        returns (address)
    {
        LaneExecutor executor = new LaneExecutor(cfg.ccipRouter, deployer);
        executor.setLaneController(controller);
        LaneController(controller).setHopRecorder(address(executor), true);

        console2.log("LaneExecutor deployed:", address(executor));
        console2.log("Post-deploy: setRemoteExecutor per lane chain; fund executor with native for CCIP fees.");
        return address(executor);
    }

    function _logSummary(string memory chainName, DeploymentResult memory result) internal pure {
        console2.log("--- Deployment summary ---");
        console2.log("Chain:", chainName);
        console2.log("LaneToken:", result.laneToken);
        console2.log("LaneController:", result.laneController);
        console2.log("LaneExecutor:", result.laneExecutor);
        console2.log("Update contracts/deployments/testnet.json with these addresses.");
    }
}
