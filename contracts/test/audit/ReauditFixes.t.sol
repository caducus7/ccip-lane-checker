// SPDX-License-Identifier: LicenseRef-Caducus-Commercial
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {LaneController} from "../../src/core/LaneController.sol";
import {LaneExecutor} from "../../src/core/LaneExecutor.sol";
import {MockCCIPRouter} from "../../src/mocks/MockCCIPRouter.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";

/// @notice Post-reaudit fixes: idle abort, permissionless settle, snapshot/timeout guards.
contract ReauditFixesTest is Test {
    LaneController public controller;
    MockERC20 public token;

    address public treasury = makeAddr("treasury");
    address public gasReserve = makeAddr("gasReserve");
    address public cre = makeAddr("cre");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public executor = makeAddr("executor");

    uint64 constant SEPOLIA = 16015286601757825753;
    uint64 constant ARBITRUM = 3478487238524512106;

    function setUp() public {
        vm.warp(1_000_000);
        token = new MockERC20("USDC", "USDC", 6);
        controller = new LaneController(address(this), address(token), treasury, gasReserve, cre);
        controller.setHopRecorder(executor, true);

        token.mint(alice, 1_000_000e6);
        token.mint(bob, 1_000_000e6);
        vm.prank(alice);
        token.approve(address(controller), type(uint256).max);
        vm.prank(bob);
        token.approve(address(controller), type(uint256).max);
    }

    function _twoLanePaths() internal pure returns (uint64[][] memory paths) {
        paths = new uint64[][](2);
        paths[0] = new uint64[](2);
        paths[0][0] = SEPOLIA;
        paths[0][1] = ARBITRUM;
        paths[1] = new uint64[](2);
        paths[1][0] = ARBITRUM;
        paths[1][1] = SEPOLIA;
    }

    function test_abortRace_usesIdleHopClock_notRaceStartAlone() public {
        vm.prank(cre);
        uint256 roundId = controller.createRound(_twoLanePaths());
        vm.prank(alice);
        controller.buyLaneTokens(roundId, 0, 100e6);
        vm.prank(bob);
        controller.buyLaneTokens(roundId, 1, 50e6);

        vm.prank(cre);
        controller.startRace(roundId);

        // Progress a hop near the end of the old wall-clock window.
        vm.warp(block.timestamp + controller.raceAbandonTimeout() - 1);
        vm.prank(executor);
        controller.recordHop(roundId, 0, SEPOLIA, block.timestamp);

        // Past racingStartedAt+timeout, but last hop was recent → not abortable for strangers.
        vm.warp(block.timestamp + 2);
        assertFalse(controller.isRaceAbortable(roundId));
        vm.prank(alice);
        vm.expectRevert(LaneController.RaceNotAbortable.selector);
        controller.abortRace(roundId);

        // Idle for full abandon timeout after last hop → permissionless abort.
        vm.warp(block.timestamp + controller.raceAbandonTimeout() + 1);
        assertTrue(controller.isRaceAbortable(roundId));
        vm.prank(alice);
        controller.abortRace(roundId);
        assertEq(uint256(controller.getRoundState(roundId)), uint256(LaneController.RoundState.Aborted));

        vm.prank(alice);
        assertEq(controller.claimRefund(roundId), 100e6);
    }

    function test_startRace_doesNotOverwriteAbandonTimeoutSnapshot() public {
        controller.setRaceAbandonTimeout(3 days);
        vm.prank(cre);
        uint256 roundId = controller.createRound(_twoLanePaths());
        vm.prank(alice);
        controller.buyLaneTokens(roundId, 0, 10e6);

        controller.setRaceAbandonTimeout(1 days);
        vm.prank(cre);
        controller.startRace(roundId);

        // Snapshot stays at create-time (3 days); 1 day after start is not enough.
        vm.warp(block.timestamp + 1 days + 1);
        assertFalse(controller.isRaceAbortable(roundId));
        vm.warp(block.timestamp + 2 days);
        assertTrue(controller.isRaceAbortable(roundId));
    }

    function test_permissionlessDistributePrizes_whenFinished() public {
        vm.prank(cre);
        uint256 roundId = controller.createRound(_twoLanePaths());
        vm.prank(alice);
        controller.buyLaneTokens(roundId, 0, 100e6);
        vm.prank(bob);
        controller.buyLaneTokens(roundId, 1, 50e6);
        vm.prank(cre);
        controller.startRace(roundId);

        vm.startPrank(executor);
        controller.recordHop(roundId, 0, SEPOLIA, block.timestamp);
        controller.recordHop(roundId, 0, ARBITRUM, block.timestamp);
        controller.recordHop(roundId, 1, ARBITRUM, block.timestamp);
        controller.recordHop(roundId, 1, SEPOLIA, block.timestamp);
        vm.stopPrank();

        assertEq(uint256(controller.getRoundState(roundId)), uint256(LaneController.RoundState.Finished));
        // Anyone may settle once Finished + runner-up resolved.
        controller.distributePrizes(roundId);
        assertEq(uint256(controller.getRoundState(roundId)), uint256(LaneController.RoundState.Settled));
    }

    function test_setClaimWindow_zeroReverts() public {
        vm.expectRevert(LaneController.ZeroClaimWindow.selector);
        controller.setClaimWindow(0);
    }

    function test_setRaceAbandonTimeout_zeroReverts() public {
        vm.expectRevert(LaneController.ZeroRaceAbandonTimeout.selector);
        controller.setRaceAbandonTimeout(0);
    }

    function test_setMinBet_zeroReverts() public {
        vm.expectRevert(LaneController.ZeroMinBet.selector);
        controller.setMinBet(0);
    }

    function test_abortRace_worksWhilePaused() public {
        vm.prank(cre);
        uint256 roundId = controller.createRound(_twoLanePaths());
        vm.prank(alice);
        controller.buyLaneTokens(roundId, 0, 25e6);
        vm.prank(cre);
        controller.startRace(roundId);

        controller.pause();
        vm.warp(block.timestamp + controller.raceAbandonTimeout() + 1);
        vm.prank(alice);
        controller.abortRace(roundId);
        vm.prank(alice);
        assertEq(controller.claimRefund(roundId), 25e6);
    }

    function test_localHop_emitsHopReceived_forCreContinuation() public {
        MockCCIPRouter router = new MockCCIPRouter();
        LaneExecutor exec = new LaneExecutor(address(router), address(this));
        exec.setCreForwarder(cre);
        exec.setHopSender(cre, true);
        exec.setAllowCcipLocalLoopback(true);
        exec.setRemoteExecutor(ARBITRUM, address(exec));
        exec.setHomeConfig(SEPOLIA, SEPOLIA, address(controller), address(exec));
        controller.setHopRecorder(address(exec), true);
        vm.deal(address(exec), 1 ether);

        vm.prank(cre);
        uint256 roundId = controller.createRound(_twoLanePaths());
        vm.prank(cre);
        controller.startRace(roundId);

        vm.expectEmit(true, true, false, true, address(exec));
        emit LaneExecutor.HopReceived(roundId, 0, SEPOLIA, 0);
        vm.prank(cre);
        exec.sendHop(roundId, 0, SEPOLIA);
        (, uint8 hops,,,,) = controller.getLane(roundId, 0);
        assertEq(hops, 1);
    }
}
