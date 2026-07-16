// SPDX-License-Identifier: LicenseRef-Caducus-Commercial
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {BroadcastScript} from "./BroadcastScript.sol";
import {LaneToken} from "../src/core/LaneToken.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {LaneController} from "../src/core/LaneController.sol";
import {LaneExecutor} from "../src/core/LaneExecutor.sol";
import {ChainConfig} from "../src/libraries/ChainConfig.sol";

/// @title DeployAll
/// @notice Multi-chain testnet deployment orchestrator for CCIP Lane Checker.
/// @dev Run once per chain with `--rpc-url` and `DEPLOY_CHAIN` set.
///
///      Phase 1 — deploy contracts on each chain (no peer env vars required):
///        DEPLOY_CHAIN=sepolia VRF_SUBSCRIPTION_ID=123 PLATFORM_TREASURY=0x... GAS_RESERVE=0x... \
///        forge script script/DeployAll.s.sol:DeployAll --rpc-url $SEPOLIA_RPC --account deployer \
///          --sender $(cast wallet address deployer) --broadcast
///      Or with PRIVATE_KEY: omit --account/--sender and export PRIVATE_KEY=0x...
///
///      Phase 2 — re-run with peer addresses filled in (or set WIRE_SELF=true on first chain):
///        REMOTE_EXECUTOR_ARBITRUM_SEPOLIA=0x... REMOTE_EXECUTOR_BASE_SEPOLIA=0x... \
///        REMOTE_LANE_TOKEN_ARBITRUM_SEPOLIA=0x... REMOTE_LANE_TOKEN_BASE_SEPOLIA=0x... \
///        forge script script/DeployAll.s.sol:DeployAll --rpc-url $SEPOLIA_RPC --broadcast
///
///      Optional overrides:
///        CRE_FORWARDER — defaults to ChainConfig.creForwarder for the target network
///        WIRE_SELF=true — map this chain's selector to the freshly deployed executor/token
contract DeployAll is BroadcastScript {
    struct DeploymentResult {
        address laneToken;
        address laneController;
        address laneExecutor;
        address creForwarder;
    }

    function run() external returns (DeploymentResult memory result) {
        address deployer = _startDeployBroadcast();
        string memory chainName = vm.envOr("DEPLOY_CHAIN", string("sepolia"));
        ChainConfig.Network network = ChainConfig.networkFromEnv(chainName);
        ChainConfig.NetworkConfig memory cfg = ChainConfig.getNetworkConfig(network);
        address creForwarder = _resolveCreForwarder(cfg);
        bool wireOnly = vm.envOr("WIRE_ONLY", false);

        console2.log("Deploying on:", cfg.name);
        console2.log("Chain ID:", cfg.chainId);
        console2.log("CCIP selector:", cfg.chainSelector);
        console2.log("CRE forwarder:", creForwarder);
        console2.log("Deployer:", deployer);
        console2.log("Wire only:", wireOnly);

        if (wireOnly) {
            result.laneToken = vm.envAddress("EXISTING_LANE_TOKEN");
            result.laneController = vm.envAddress("EXISTING_LANE_CONTROLLER");
            result.laneExecutor = vm.envAddress("EXISTING_LANE_EXECUTOR");
            result.creForwarder = creForwarder;
            _wireExisting(cfg, result, creForwarder);
        } else {
            result.laneToken = _deployLaneToken(cfg);
            result.laneController = _deployLaneController(cfg, deployer, creForwarder);
            result.laneExecutor = _deployLaneExecutor(cfg, deployer, result.laneController, creForwarder);
            result.creForwarder = creForwarder;
            _wireLaneToken(LaneToken(payable(result.laneToken)), cfg, result.laneExecutor);
            _wireRemotePeers(cfg, result.laneExecutor, result.laneToken);
            _configureCreWorkflowAllowlists(
                LaneController(result.laneController), LaneExecutor(payable(result.laneExecutor))
            );
        }

        vm.stopBroadcast();

        _logSummary(cfg.name, result);
    }

    function _wireExisting(ChainConfig.NetworkConfig memory cfg, DeploymentResult memory result, address creForwarder)
        internal
    {
        LaneExecutor executor = LaneExecutor(payable(result.laneExecutor));
        LaneController controller = LaneController(result.laneController);

        executor.setLaneController(result.laneController);
        executor.setCreForwarder(creForwarder);
        executor.setHopSender(creForwarder, true);
        _wireHomeConfig(cfg, result.laneController, result.laneExecutor);
        controller.setHopRecorder(result.laneExecutor, true);
        controller.setCreForwarder(creForwarder);
        _configureCreWorkflowAllowlists(controller, executor);

        _wireLaneToken(LaneToken(payable(result.laneToken)), cfg, result.laneExecutor);
        _wireRemotePeers(cfg, result.laneExecutor, result.laneToken);
    }

    function _resolveCreForwarder(ChainConfig.NetworkConfig memory cfg) internal view returns (address) {
        address envForwarder = vm.envOr("CRE_FORWARDER", address(0));
        return envForwarder == address(0) ? cfg.creForwarder : envForwarder;
    }

    /// @dev Require CRE_WORKFLOW_OWNER and/or CRE_WORKFLOW_ID unless CRE_ALLOWLIST_OPTIONAL=true (local only).
    function _configureCreWorkflowAllowlists(LaneController controller, LaneExecutor executor) internal {
        address workflowOwner = vm.envOr("CRE_WORKFLOW_OWNER", address(0));
        bytes32 workflowId = vm.envOr("CRE_WORKFLOW_ID", bytes32(0));
        bool optional = vm.envOr("CRE_ALLOWLIST_OPTIONAL", false);

        if (workflowOwner == address(0) && workflowId == bytes32(0)) {
            if (!optional) {
                revert("DeployAll: set CRE_WORKFLOW_OWNER and/or CRE_WORKFLOW_ID (or CRE_ALLOWLIST_OPTIONAL=true)");
            }
            console2.log("CRE workflow allowlists skipped (CRE_ALLOWLIST_OPTIONAL)");
            return;
        }

        if (workflowOwner != address(0)) {
            controller.setAllowedWorkflowOwner(workflowOwner, true);
            executor.setAllowedWorkflowOwner(workflowOwner, true);
            console2.log("CRE workflow owner allowlisted:", workflowOwner);
        }
        if (workflowId != bytes32(0)) {
            controller.setAllowedWorkflowId(workflowId, true);
            executor.setAllowedWorkflowId(workflowId, true);
            console2.log("CRE workflow id allowlisted");
        }
    }

    function _deployLaneToken(ChainConfig.NetworkConfig memory cfg) internal returns (address) {
        uint256 vrfSubId = vm.envUint("VRF_SUBSCRIPTION_ID");
        uint256[] memory supportedChains = ChainConfig.supportedChainSelectors();

        LaneToken token = new LaneToken(
            cfg.ccipRouter,
            cfg.linkToken,
            cfg.vrfCoordinator,
            vrfSubId,
            cfg.vrfKeyHash,
            cfg.chainId,
            cfg.chainSelector,
            supportedChains
        );

        console2.log("LaneToken deployed:", address(token));
        console2.log("Post-deploy: fund LaneToken with native for CCIP fees (plain transfer to its address).");
        return address(token);
    }

    function _deployLaneController(ChainConfig.NetworkConfig memory cfg, address deployer, address creForwarder)
        internal
        returns (address)
    {
        address treasury = vm.envOr("PLATFORM_TREASURY", deployer);
        address gasReserve = vm.envOr("GAS_RESERVE", deployer);

        LaneController controller = new LaneController(deployer, cfg.linkToken, treasury, gasReserve, creForwarder);

        // DEFAULT_MIN_BET is 1e6 (6-decimal USDC). LINK is 18 decimals — set ~1 LINK.
        uint8 decimals = IERC20Metadata(cfg.linkToken).decimals();
        uint256 configuredMinBet = 10 ** uint256(decimals);
        controller.setMinBet(configuredMinBet);
        console2.log("LaneController minBet set for token decimals:", decimals);
        console2.log("minBet:", configuredMinBet);

        console2.log("LaneController deployed:", address(controller));
        return address(controller);
    }

    function _deployLaneExecutor(
        ChainConfig.NetworkConfig memory cfg,
        address deployer,
        address controller,
        address creForwarder
    ) internal returns (address) {
        LaneExecutor executor = new LaneExecutor(cfg.ccipRouter, deployer);

        executor.setLaneController(controller);
        executor.setCreForwarder(creForwarder);
        executor.setHopSender(creForwarder, true);
        _wireHomeConfig(cfg, controller, address(executor));
        LaneController(controller).setHopRecorder(address(executor), true);

        console2.log("LaneExecutor deployed:", address(executor));
        console2.log("Hop recorder wired on LaneController");
        return address(executor);
    }

    function _wireLaneToken(LaneToken token, ChainConfig.NetworkConfig memory cfg, address localExecutor) internal {
        // Never map this chain's selector to address(this) for bridging — self-bridge is forbidden.
        bool wireSelf = vm.envOr("WIRE_SELF", false);
        if (wireSelf) {
            console2.log("WIRE_SELF: skip self LaneToken peer map (SelfBridgeForbidden). Wire real remotes in phase 2.");
        }

        // Parimutuel races use LaneExecutor; solo LaneToken hops are independent.
        // Fund executor with native token for CCIP fees after deploy.
        console2.log("Fund LaneExecutor with native for CCIP:", localExecutor);
        console2.log("LaneToken local selector:", cfg.chainSelector);
    }

    function _wireRemotePeers(
        ChainConfig.NetworkConfig memory cfg,
        address localExecutor,
        address localLaneToken
    ) internal {
        ChainConfig.NetworkConfig[3] memory networks = ChainConfig.allNetworks();
        bool wireSelf = vm.envOr("WIRE_SELF", false);

        for (uint256 i = 0; i < networks.length; i++) {
            ChainConfig.NetworkConfig memory peer = networks[i];
            if (peer.chainSelector == cfg.chainSelector) continue;

            address remoteExecutor = _remoteExecutorAddress(peer);
            if (remoteExecutor == address(0) && wireSelf) {
                remoteExecutor = localExecutor;
            }
            if (remoteExecutor != address(0)) {
                LaneExecutor(payable(localExecutor)).setRemoteExecutor(peer.chainSelector, remoteExecutor);
                console2.log("Remote executor set:", peer.chainSelector, remoteExecutor);
            } else {
                console2.log("Skip remote executor (unset):", peer.name);
            }

            address remoteLaneToken = _remoteLaneTokenAddress(peer);
            if (remoteLaneToken == address(0) && wireSelf) {
                // Do not point peer selectors at the local token — that enables self-bridge / wrong-chain sends.
                console2.log("WIRE_SELF: skip LaneToken peer (need real REMOTE_LANE_TOKEN_*):", peer.name);
                remoteLaneToken = address(0);
            }
            if (remoteLaneToken != address(0)) {
                if (remoteLaneToken == localLaneToken) {
                    console2.log("Skip LaneToken peer (same as local):", peer.chainSelector);
                } else {
                    LaneToken(payable(localLaneToken)).setRemoteLaneToken(peer.chainSelector, remoteLaneToken);
                    console2.log("Remote lane token set:", peer.chainSelector, remoteLaneToken);
                }
            } else {
                console2.log("Skip remote lane token (unset):", peer.name);
            }
        }
    }

    function _remoteExecutorAddress(ChainConfig.NetworkConfig memory peer) internal view returns (address) {
        if (peer.network == ChainConfig.Network.Sepolia) {
            return vm.envOr("REMOTE_EXECUTOR_SEPOLIA", address(0));
        }
        if (peer.network == ChainConfig.Network.ArbitrumSepolia) {
            return vm.envOr("REMOTE_EXECUTOR_ARBITRUM_SEPOLIA", address(0));
        }
        if (peer.network == ChainConfig.Network.BaseSepolia) {
            return vm.envOr("REMOTE_EXECUTOR_BASE_SEPOLIA", address(0));
        }
        return address(0);
    }

    function _remoteLaneTokenAddress(ChainConfig.NetworkConfig memory peer) internal view returns (address) {
        if (peer.network == ChainConfig.Network.Sepolia) {
            return vm.envOr("REMOTE_LANE_TOKEN_SEPOLIA", address(0));
        }
        if (peer.network == ChainConfig.Network.ArbitrumSepolia) {
            return vm.envOr("REMOTE_LANE_TOKEN_ARBITRUM_SEPOLIA", address(0));
        }
        if (peer.network == ChainConfig.Network.BaseSepolia) {
            return vm.envOr("REMOTE_LANE_TOKEN_BASE_SEPOLIA", address(0));
        }
        return address(0);
    }

    function _wireHomeConfig(
        ChainConfig.NetworkConfig memory cfg,
        address controller,
        address executorAddr
    ) internal {
        uint64 homeSelector = uint64(vm.envOr("HOME_CHAIN_SELECTOR", uint256(ChainConfig.SEPOLIA_SELECTOR)));
        address canonicalController = vm.envOr("CANONICAL_CONTROLLER", controller);
        address homeExecutor = vm.envOr("HOME_EXECUTOR", executorAddr);

        LaneExecutor(payable(executorAddr)).setHomeConfig(
            cfg.chainSelector, homeSelector, canonicalController, homeExecutor
        );
        console2.log("Home chain selector:", homeSelector);
        console2.log("Canonical controller:", canonicalController);
        console2.log("Home executor:", homeExecutor);
    }

    function _logSummary(string memory chainName, DeploymentResult memory result) internal view {
        console2.log("--- Deployment summary ---");
        console2.log("Chain:", chainName);
        console2.log("LaneToken:", result.laneToken);
        console2.log("LaneController:", result.laneController);
        console2.log("LaneExecutor:", result.laneExecutor);
        console2.log("CRE forwarder:", result.creForwarder);
        console2.log("Update contracts/deployments/testnet.json with these addresses.");
        console2.log("Re-run peer wiring on each chain once all executors/tokens are deployed.");
    }
}
