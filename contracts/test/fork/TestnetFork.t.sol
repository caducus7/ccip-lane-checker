// SPDX-License-Identifier: LicenseRef-Caducus-Commercial
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ChainConfig} from "../../src/libraries/ChainConfig.sol";
import {LaneToken} from "../../src/core/LaneToken.sol";
import {LaneController} from "../../src/core/LaneController.sol";
import {LaneExecutor} from "../../src/core/LaneExecutor.sol";

/// @title TestnetForkBase
/// @notice Shared plumbing for testnet fork smoke tests. Every test self-skips when
///         the corresponding RPC env var (SEPOLIA_RPC / ARBITRUM_SEPOLIA_RPC /
///         BASE_SEPOLIA_RPC) is unset, so `forge test` stays green in CI without RPC.
///         See test/fork/README.md for how to run these against live testnets.
abstract contract TestnetForkBase is Test {
    /// @dev Forks the chain for `rpcEnvVar` or skips the test when the var is unset.
    function _forkOrSkip(string memory rpcEnvVar) internal returns (bool forked) {
        string memory rpcUrl = vm.envOr(rpcEnvVar, string(""));
        vm.skip(bytes(rpcUrl).length == 0);
        if (bytes(rpcUrl).length == 0) return false;
        vm.createSelectFork(rpcUrl);
        return true;
    }

    /// @dev Deployed-contract address from env (e.g. LANE_TOKEN_SEPOLIA), or zero when
    ///      not yet deployed. Fill deployments/testnet.json + these env vars post-deploy.
    function _deployedOrZero(string memory envVar) internal view returns (address) {
        return vm.envOr(envVar, address(0));
    }

    /// @dev Canonical Chainlink infra sanity checks shared by all three chains:
    ///      the CCIP router, LINK token and VRF coordinator must be live contracts,
    ///      and the router must support lanes to the two sibling testnets.
    function _assertInfra(ChainConfig.NetworkConfig memory cfg, uint64[2] memory siblings) internal view {
        assertEq(block.chainid, cfg.chainId, "forked wrong chain");

        assertGt(cfg.ccipRouter.code.length, 0, "CCIP router not deployed");
        assertGt(cfg.linkToken.code.length, 0, "LINK token not deployed");
        assertGt(cfg.vrfCoordinator.code.length, 0, "VRF coordinator not deployed");

        // LINK responds like an ERC20.
        assertGt(IERC20(cfg.linkToken).totalSupply(), 0, "LINK totalSupply");

        // Router exposes lanes to the other two supported testnets.
        for (uint256 i = 0; i < siblings.length; i++) {
            assertTrue(
                IRouterClient(cfg.ccipRouter).isChainSupported(siblings[i]),
                "router lane to sibling chain unsupported"
            );
        }
    }

    /// @dev Post-deploy wiring checks. Each block is a placeholder that activates once
    ///      the matching env var is set to the deployed address; until then it is a no-op
    ///      so the scaffold passes (as skipped work) right after a fresh clone.
    function _assertDeployment(
        ChainConfig.NetworkConfig memory cfg,
        address laneToken,
        address laneController,
        address laneExecutor,
        uint64[2] memory siblings
    ) internal view {
        if (laneToken != address(0)) {
            assertGt(laneToken.code.length, 0, "LaneToken not deployed");
            LaneToken lt = LaneToken(payable(laneToken));
            assertEq(address(lt.s_router()), cfg.ccipRouter, "LaneToken router mismatch");
            for (uint256 i = 0; i < siblings.length; i++) {
                assertTrue(
                    lt.remoteLaneTokens(siblings[i]) != address(0),
                    "LaneToken peer not wired for sibling chain"
                );
            }
        }

        if (laneExecutor != address(0)) {
            assertGt(laneExecutor.code.length, 0, "LaneExecutor not deployed");
            LaneExecutor ex = LaneExecutor(payable(laneExecutor));
            assertEq(address(ex.s_ccipRouter()), cfg.ccipRouter, "LaneExecutor router mismatch");
            for (uint256 i = 0; i < siblings.length; i++) {
                assertTrue(
                    ex.remoteExecutors(siblings[i]) != address(0),
                    "LaneExecutor peer not wired for sibling chain"
                );
            }
            if (laneController != address(0)) {
                assertEq(ex.laneController(), laneController, "executor -> controller wiring");
            }
        }

        if (laneController != address(0)) {
            assertGt(laneController.code.length, 0, "LaneController not deployed");
            LaneController ctrl = LaneController(laneController);
            assertEq(ctrl.creForwarder(), cfg.creForwarder, "controller CRE forwarder mismatch");
            if (laneExecutor != address(0)) {
                assertTrue(ctrl.hopRecorders(laneExecutor), "executor not a hop recorder");
            }
        }
    }
}

/// @notice Ethereum Sepolia fork smoke. Runs only when SEPOLIA_RPC is set.
contract SepoliaForkTest is TestnetForkBase {
    function test_fork_Sepolia_InfraLive() public {
        _forkOrSkip("SEPOLIA_RPC");
        _assertInfra(
            ChainConfig.sepoliaConfig(),
            [ChainConfig.ARBITRUM_SEPOLIA_SELECTOR, ChainConfig.BASE_SEPOLIA_SELECTOR]
        );
    }

    function test_fork_Sepolia_DeploymentWired() public {
        _forkOrSkip("SEPOLIA_RPC");
        // Placeholder: activates once LANE_*_SEPOLIA env vars point at deployed contracts.
        _assertDeployment(
            ChainConfig.sepoliaConfig(),
            _deployedOrZero("LANE_TOKEN_SEPOLIA"),
            _deployedOrZero("LANE_CONTROLLER_SEPOLIA"),
            _deployedOrZero("LANE_EXECUTOR_SEPOLIA"),
            [ChainConfig.ARBITRUM_SEPOLIA_SELECTOR, ChainConfig.BASE_SEPOLIA_SELECTOR]
        );
    }
}

/// @notice Arbitrum Sepolia fork smoke. Runs only when ARBITRUM_SEPOLIA_RPC is set.
contract ArbitrumSepoliaForkTest is TestnetForkBase {
    function test_fork_ArbitrumSepolia_InfraLive() public {
        _forkOrSkip("ARBITRUM_SEPOLIA_RPC");
        _assertInfra(
            ChainConfig.arbitrumSepoliaConfig(),
            [ChainConfig.SEPOLIA_SELECTOR, ChainConfig.BASE_SEPOLIA_SELECTOR]
        );
    }

    function test_fork_ArbitrumSepolia_DeploymentWired() public {
        _forkOrSkip("ARBITRUM_SEPOLIA_RPC");
        _assertDeployment(
            ChainConfig.arbitrumSepoliaConfig(),
            _deployedOrZero("LANE_TOKEN_ARBITRUM_SEPOLIA"),
            _deployedOrZero("LANE_CONTROLLER_ARBITRUM_SEPOLIA"),
            _deployedOrZero("LANE_EXECUTOR_ARBITRUM_SEPOLIA"),
            [ChainConfig.SEPOLIA_SELECTOR, ChainConfig.BASE_SEPOLIA_SELECTOR]
        );
    }
}

/// @notice Base Sepolia fork smoke. Runs only when BASE_SEPOLIA_RPC is set.
contract BaseSepoliaForkTest is TestnetForkBase {
    function test_fork_BaseSepolia_InfraLive() public {
        _forkOrSkip("BASE_SEPOLIA_RPC");
        _assertInfra(
            ChainConfig.baseSepoliaConfig(),
            [ChainConfig.SEPOLIA_SELECTOR, ChainConfig.ARBITRUM_SEPOLIA_SELECTOR]
        );
    }

    function test_fork_BaseSepolia_DeploymentWired() public {
        _forkOrSkip("BASE_SEPOLIA_RPC");
        _assertDeployment(
            ChainConfig.baseSepoliaConfig(),
            _deployedOrZero("LANE_TOKEN_BASE_SEPOLIA"),
            _deployedOrZero("LANE_CONTROLLER_BASE_SEPOLIA"),
            _deployedOrZero("LANE_EXECUTOR_BASE_SEPOLIA"),
            [ChainConfig.SEPOLIA_SELECTOR, ChainConfig.ARBITRUM_SEPOLIA_SELECTOR]
        );
    }
}
