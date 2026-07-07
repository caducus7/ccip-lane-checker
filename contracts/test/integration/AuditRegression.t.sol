// SPDX-License-Identifier: LicenseRef-Caducus-Commercial
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CCIPLocalSimulator} from "@chainlink/local/src/ccip/CCIPLocalSimulator.sol";
import {BurnMintERC677Helper} from "@chainlink/local/src/ccip/BurnMintERC677Helper.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {LaneController} from "../../src/core/LaneController.sol";
import {LaneExecutor} from "../../src/core/LaneExecutor.sol";
import {LaneToken} from "../../src/core/LaneToken.sol";
import {ChainConfig} from "../../src/libraries/ChainConfig.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockVRFCoordinatorV2Plus} from "../../src/mocks/MockVRFCoordinatorV2Plus.sol";

/// @notice Regression tests closing audit findings with end-to-end scenarios.
contract AuditRegressionTest is Test {
    CCIPLocalSimulator public simulator;
    LaneController public controller;
    LaneExecutor public executor;
    MockERC20 public token;

    address public treasury = makeAddr("treasury");
    address public gasReserve = makeAddr("gasReserve");
    address public cre = makeAddr("cre");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint64 public localSelector;

    function setUp() public {
        vm.warp(1_000_000);
        simulator = new CCIPLocalSimulator();
        (, IRouterClient router,,,,,) = simulator.configuration();
        localSelector = ChainConfig.SEPOLIA_SELECTOR;

        token = new MockERC20("USDC", "USDC", 6);
        controller = new LaneController(address(this), address(token), treasury, gasReserve, cre);
        executor = new LaneExecutor(address(router), address(this));

        executor.setLaneController(address(controller));
        executor.setHomeConfig(localSelector, localSelector, address(controller), address(executor));
        controller.setHopRecorder(address(executor), true);
        executor.setRemoteExecutor(localSelector, address(executor));
        executor.setRemoteExecutor(ChainConfig.SEPOLIA_SELECTOR, address(executor));
        executor.setRemoteExecutor(ChainConfig.ARBITRUM_SEPOLIA_SELECTOR, address(executor));
        executor.setRemoteExecutor(ChainConfig.BASE_SEPOLIA_SELECTOR, address(executor));
        executor.setHopSender(cre, true);

        token.mint(alice, 1000e6);
        token.mint(bob, 1000e6);
        vm.prank(alice);
        token.approve(address(controller), type(uint256).max);
        vm.prank(bob);
        token.approve(address(controller), type(uint256).max);
    }

    function _lanePaths() internal pure returns (uint64[][] memory paths) {
        paths = new uint64[][](2);
        paths[0] = new uint64[](2);
        paths[0][0] = ChainConfig.ARBITRUM_SEPOLIA_SELECTOR;
        paths[0][1] = ChainConfig.BASE_SEPOLIA_SELECTOR;
        paths[1] = new uint64[](2);
        paths[1][0] = ChainConfig.BASE_SEPOLIA_SELECTOR;
        paths[1][1] = ChainConfig.ARBITRUM_SEPOLIA_SELECTOR;
    }

    function test_parimutuel_cannotSettleBeforeRunnerUpFinishes() public {
        vm.prank(cre);
        uint256 roundId = controller.createRound(_lanePaths());
        vm.prank(alice);
        controller.buyLaneTokens(roundId, 0, 100e6);
        vm.prank(bob);
        controller.buyLaneTokens(roundId, 1, 300e6);
        vm.prank(cre);
        controller.startRace(roundId);

        vm.prank(cre);
        executor.sendHop(roundId, 0, ChainConfig.ARBITRUM_SEPOLIA_SELECTOR);
        vm.prank(cre);
        executor.sendHop(roundId, 0, ChainConfig.BASE_SEPOLIA_SELECTOR);

        vm.prank(cre);
        vm.expectRevert(LaneController.RunnerUpPending.selector);
        controller.distributePrizes(roundId);
    }

    function test_sweepBlocksFurtherClaims() public {
        vm.prank(cre);
        uint256 roundId = controller.createRound(_lanePaths());
        vm.prank(alice);
        controller.buyLaneTokens(roundId, 0, 100e6);
        vm.prank(cre);
        controller.startRace(roundId);

        vm.startPrank(cre);
        executor.sendHop(roundId, 0, ChainConfig.ARBITRUM_SEPOLIA_SELECTOR);
        executor.sendHop(roundId, 0, ChainConfig.BASE_SEPOLIA_SELECTOR);
        executor.sendHop(roundId, 1, ChainConfig.BASE_SEPOLIA_SELECTOR);
        executor.sendHop(roundId, 1, ChainConfig.ARBITRUM_SEPOLIA_SELECTOR);
        controller.distributePrizes(roundId);
        vm.stopPrank();

        vm.warp(block.timestamp + controller.claimWindow() + 1);
        vm.prank(cre);
        controller.sweepUnclaimed(roundId);

        vm.prank(alice);
        vm.expectRevert(LaneController.ClaimsSwept.selector);
        controller.claimPrize(roundId);
    }

    function test_solo_selfLoopCompletes() public {
        CCIPLocalSimulator soloSim = new CCIPLocalSimulator();
        (uint64 sel, IRouterClient router,,,, BurnMintERC677Helper bnM,) = soloSim.configuration();
        MockVRFCoordinatorV2Plus vrf = new MockVRFCoordinatorV2Plus();
        uint256[] memory chains = new uint256[](1);
        chains[0] = sel;

        LaneToken laneToken = new LaneToken(
            address(router), address(bnM), address(vrf), 1, bytes32(0), block.chainid, sel, chains
        );
        laneToken.setRemoteLaneToken(sel, address(laneToken));

        address player = makeAddr("player");
        bnM.drip(player);
        vm.startPrank(player);
        bnM.approve(address(laneToken), 1e18);
        laneToken.deposit(1e18);
        laneToken.startGame(sel, 1e18, 1);
        vm.stopPrank();

        (,,,,,, bool active) = laneToken.getGameRound(1);
        assertFalse(active);
        assertEq(laneToken.s_balances(player), 1e18);
    }
}
