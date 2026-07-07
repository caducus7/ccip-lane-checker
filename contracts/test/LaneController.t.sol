// SPDX-License-Identifier: LicenseRef-Caducus-Commercial
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {LaneController} from "../src/core/LaneController.sol";
import {PrizeCalculator} from "../src/libraries/PrizeCalculator.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

contract LaneControllerTest is Test {
    LaneController public controller;
    MockERC20 public token;

    address public treasury = makeAddr("treasury");
    address public gasReserve = makeAddr("gasReserve");
    address public cre = makeAddr("cre");
    address public player = makeAddr("player");
    address public rival = makeAddr("rival");
    address public executor = makeAddr("executor");

    uint64 constant SEPOLIA = 16015286601757825753;
    uint64 constant ARBITRUM = 3478487238524512106;

    event RoundCreated(uint256 indexed roundId, uint8 laneCount);
    event BetPlaced(uint256 indexed roundId, uint8 indexed laneId, address indexed bettor, uint256 amount);
    event RaceStarted(uint256 indexed roundId);
    event HopCompleted(
        uint256 indexed roundId, uint8 indexed laneId, uint64 chainSelector, uint256 latency, uint8 hopIndex
    );
    event LaneFinished(uint256 indexed roundId, uint8 indexed laneId, uint256 finishTime);
    event WinnerDeclared(uint256 indexed roundId, uint8 indexed laneId, uint256 finishTime);
    event PrizesDistributed(uint256 indexed roundId, uint8 winnerLaneId, uint256 winnerPayout);
    event RoundCooldownUpdated(uint48 cooldown);

    function setUp() public {
        vm.warp(1_000_000);
        token = new MockERC20("USDC", "USDC", 6);
        controller = new LaneController(address(this), address(token), treasury, gasReserve, cre);
        controller.setHopRecorder(executor, true);

        token.mint(player, 1_000_000e6);
        token.mint(rival, 1_000_000e6);
        vm.prank(player);
        token.approve(address(controller), type(uint256).max);
        vm.prank(rival);
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

    function _createRound() internal returns (uint256 roundId) {
        vm.prank(cre);
        roundId = controller.createRound(_twoLanePaths());
    }

    function _finishLane(uint256 roundId, uint8 laneId) internal {
        (uint64[] memory path,,,,,) = controller.getLane(roundId, laneId);
        vm.startPrank(executor);
        controller.recordHop(roundId, laneId, path[0], block.timestamp - 120);
        controller.recordHop(roundId, laneId, path[1], block.timestamp - 90);
        vm.stopPrank();
    }

    function _sendTime(uint256 latencyAgo) internal view returns (uint256) {
        return block.timestamp - latencyAgo;
    }

    // ---------------------------------------------------------------- lifecycle

    function test_parimutuelRound_fullLifecycle() public {
        uint256 roundId = _createRound();
        assertEq(roundId, 1);

        vm.prank(player);
        controller.buyLaneTokens(roundId, 0, 100e6);
        vm.prank(rival);
        controller.buyLaneTokens(roundId, 1, 300e6);

        assertEq(controller.getTotalPrizePool(roundId), 400e6);
        assertEq(controller.getLanePool(roundId, 0), 100e6);
        assertEq(controller.getLanePool(roundId, 1), 300e6);

        vm.prank(cre);
        vm.expectEmit(true, false, false, false);
        emit RaceStarted(roundId);
        controller.startRace(roundId);

        _finishLane(roundId, 0);
        assertEq(controller.getRoundWinner(roundId), 0);
        assertEq(uint256(controller.getRoundState(roundId)), uint256(LaneController.RoundState.Finished));

        // Runner-up lane completes after the winner.
        _finishLane(roundId, 1);
        assertEq(controller.getRoundRunnerUp(roundId), 1);

        vm.prank(cre);
        controller.distributePrizes(roundId);
        assertEq(uint256(controller.getRoundState(roundId)), uint256(LaneController.RoundState.Settled));

        PrizeCalculator.Payout memory p = PrizeCalculator.calculate(400e6);
        assertEq(token.balanceOf(treasury), p.platform);
        assertEq(token.balanceOf(gasReserve), p.gasReserve);

        // Sole bettor on each lane claims the full lane share.
        uint256 playerBefore = token.balanceOf(player);
        vm.prank(player);
        uint256 playerPrize = controller.claimPrize(roundId);
        assertEq(playerPrize, p.winner);
        assertEq(token.balanceOf(player), playerBefore + p.winner);

        vm.prank(rival);
        uint256 rivalPrize = controller.claimPrize(roundId);
        assertEq(rivalPrize, p.runnerUp);
    }

    function test_declareWinner_creGated() public {
        uint256 roundId = _createRound();
        vm.prank(cre);
        controller.startRace(roundId);

        // Finish lane 1 first, but suppose CRE wants to declare explicitly: it can't
        // re-declare after recordHop already declared the first finisher.
        _finishLane(roundId, 1);

        vm.prank(cre);
        vm.expectRevert(LaneController.WinnerAlreadyDeclared.selector);
        controller.declareWinner(roundId, 1);

        assertEq(controller.getRoundWinner(roundId), 1);
    }

    function test_claimPrize_proRataSplit() public {
        uint256 roundId = _createRound();

        vm.prank(player);
        controller.buyLaneTokens(roundId, 0, 100e6);
        vm.prank(rival);
        controller.buyLaneTokens(roundId, 0, 300e6);

        vm.prank(cre);
        controller.startRace(roundId);
        _finishLane(roundId, 0);
        vm.prank(cre);
        controller.distributePrizes(roundId);

        PrizeCalculator.Payout memory p = PrizeCalculator.calculate(400e6);

        vm.prank(player);
        assertEq(controller.claimPrize(roundId), p.winner / 4);
        vm.prank(rival);
        assertEq(controller.claimPrize(roundId), (p.winner * 3) / 4);

        // Double claim reverts.
        vm.prank(player);
        vm.expectRevert(LaneController.NothingToClaim.selector);
        controller.claimPrize(roundId);
    }

    function test_distributePrizes_noWinnerLaneBets_sweepsToPlatform() public {
        uint256 roundId = _createRound();

        // All bets on lane 1, but lane 0 wins and no runner-up finishes.
        vm.prank(player);
        controller.buyLaneTokens(roundId, 1, 200e6);

        vm.prank(cre);
        controller.startRace(roundId);
        _finishLane(roundId, 0);
        vm.prank(cre);
        controller.distributePrizes(roundId);

        PrizeCalculator.Payout memory p = PrizeCalculator.calculate(200e6);
        // Winner share (no winner-lane bettors) and runner-up share (no runner-up) sweep to platform.
        assertEq(token.balanceOf(treasury), p.platform + p.winner + p.runnerUp);
        assertEq(token.balanceOf(gasReserve), p.gasReserve);
    }

    // ---------------------------------------------------------------- access control

    function test_accessControl() public {
        uint64[][] memory paths = _twoLanePaths();

        vm.startPrank(player);
        vm.expectRevert(LaneController.NotAuthorized.selector);
        controller.createRound(paths);
        vm.stopPrank();

        uint256 roundId = _createRound();

        vm.startPrank(player);
        vm.expectRevert(LaneController.NotAuthorized.selector);
        controller.startRace(roundId);
        vm.expectRevert(LaneController.NotAuthorized.selector);
        controller.recordHop(roundId, 0, SEPOLIA, _sendTime(10));
        vm.expectRevert(LaneController.NotAuthorized.selector);
        controller.declareWinner(roundId, 0);
        vm.expectRevert(LaneController.NotAuthorized.selector);
        controller.distributePrizes(roundId);
        vm.stopPrank();

        // Owner is also allowed for admin functions.
        controller.startRace(roundId);
    }

    function test_pause_blocksEntrypoints() public {
        uint256 roundId = _createRound();
        controller.pause();

        vm.prank(player);
        vm.expectRevert();
        controller.buyLaneTokens(roundId, 0, 1e6);

        vm.prank(cre);
        vm.expectRevert();
        controller.startRace(roundId);

        controller.unpause();
        vm.prank(cre);
        controller.startRace(roundId);
    }

    // ---------------------------------------------------------------- state machine

    function test_stateMachine_invalidTransitionsRevert() public {
        uint256 roundId = _createRound();

        // Cannot record hops or distribute during Betting.
        vm.prank(executor);
        vm.expectRevert(LaneController.InvalidState.selector);
        controller.recordHop(roundId, 0, SEPOLIA, _sendTime(10));

        vm.prank(cre);
        vm.expectRevert(LaneController.NoWinner.selector);
        controller.distributePrizes(roundId);

        vm.prank(cre);
        controller.startRace(roundId);

        // Cannot bet or restart during Racing.
        vm.prank(player);
        vm.expectRevert(LaneController.BettingClosed.selector);
        controller.buyLaneTokens(roundId, 0, 1e6);

        vm.prank(cre);
        vm.expectRevert(LaneController.InvalidState.selector);
        controller.startRace(roundId);

        _finishLane(roundId, 0);

        // Finished lane cannot record more hops.
        vm.prank(executor);
        vm.expectRevert(LaneController.InvalidState.selector);
        controller.recordHop(roundId, 0, SEPOLIA, _sendTime(10));

        vm.prank(cre);
        controller.distributePrizes(roundId);

        // Settled: no more hops or double distribution.
        vm.prank(executor);
        vm.expectRevert(LaneController.InvalidState.selector);
        controller.recordHop(roundId, 1, SEPOLIA, _sendTime(10));

        vm.prank(cre);
        vm.expectRevert(LaneController.AlreadySettled.selector);
        controller.distributePrizes(roundId);
    }

    function test_createRound_validation() public {
        vm.startPrank(cre);

        uint64[][] memory onePath = new uint64[][](1);
        onePath[0] = new uint64[](1);
        onePath[0][0] = SEPOLIA;
        vm.expectRevert("bad lane count");
        controller.createRound(onePath);

        uint64[][] memory withEmpty = new uint64[][](2);
        withEmpty[0] = new uint64[](1);
        withEmpty[0][0] = SEPOLIA;
        withEmpty[1] = new uint64[](0);
        vm.expectRevert("empty path");
        controller.createRound(withEmpty);

        uint64[][] memory tooLong = new uint64[][](2);
        tooLong[0] = new uint64[](1);
        tooLong[0][0] = SEPOLIA;
        tooLong[1] = new uint64[](controller.MAX_HOPS() + 1);
        vm.expectRevert("path too long");
        controller.createRound(tooLong);

        vm.stopPrank();
    }

    function test_invalidRoundAndLane() public {
        vm.expectRevert(LaneController.InvalidRound.selector);
        controller.getRoundWinner(42);

        uint256 roundId = _createRound();
        vm.prank(player);
        vm.expectRevert(LaneController.InvalidLane.selector);
        controller.buyLaneTokens(roundId, 5, 1e6);
    }

    // ---------------------------------------------------------------- fuzz

    /// @dev Betting accounting: pools always sum, transfers always match.
    function testFuzz_buyLaneTokens_accounting(uint96 amountA, uint96 amountB, bool sameLane) public {
        amountA = uint96(bound(amountA, 1, 500_000e6));
        amountB = uint96(bound(amountB, 1, 500_000e6));

        uint256 roundId = _createRound();

        vm.prank(player);
        controller.buyLaneTokens(roundId, 0, amountA);
        uint8 laneB = sameLane ? 0 : 1;
        vm.prank(rival);
        controller.buyLaneTokens(roundId, laneB, amountB);

        assertEq(controller.getTotalPrizePool(roundId), uint256(amountA) + amountB);
        assertEq(
            controller.getLanePool(roundId, 0) + controller.getLanePool(roundId, 1), uint256(amountA) + amountB
        );
        assertEq(token.balanceOf(address(controller)), uint256(amountA) + amountB);
    }

    /// @dev Settlement conservation: treasury + gasReserve + claims == total pool (winner-lane-only bets).
    function testFuzz_settlement_conservation(uint96 betWinner, uint96 betRunnerUp) public {
        betWinner = uint96(bound(betWinner, 1, 500_000e6));
        betRunnerUp = uint96(bound(betRunnerUp, 1, 500_000e6));

        uint256 roundId = _createRound();
        vm.prank(player);
        controller.buyLaneTokens(roundId, 0, betWinner);
        vm.prank(rival);
        controller.buyLaneTokens(roundId, 1, betRunnerUp);

        vm.prank(cre);
        controller.startRace(roundId);
        _finishLane(roundId, 0);
        _finishLane(roundId, 1);
        vm.prank(cre);
        controller.distributePrizes(roundId);

        vm.prank(player);
        uint256 winnerClaim = controller.claimPrize(roundId);
        vm.prank(rival);
        uint256 runnerUpClaim = controller.claimPrize(roundId);

        uint256 distributed =
            token.balanceOf(treasury) + token.balanceOf(gasReserve) + winnerClaim + runnerUpClaim;
        uint256 pool = uint256(betWinner) + betRunnerUp;

        // Claims round down; dust (< 2 wei here since each lane has one bettor: zero dust) stays in contract.
        assertLe(distributed, pool);
        assertLe(pool - distributed, 2);
    }

    /// @dev First lane to complete its circuit always wins, regardless of hop order before that.
    function testFuzz_firstFinisherWins(uint8 firstLane) public {
        uint8 winner = uint8(bound(firstLane, 0, 1));
        uint8 loser = winner == 0 ? 1 : 0;

        uint256 roundId = _createRound();
        vm.prank(cre);
        controller.startRace(roundId);

        // Interleave: loser makes progress but winner completes first.
        (uint64[] memory loserPath,,,,,) = controller.getLane(roundId, loser);
        vm.prank(executor);
        controller.recordHop(roundId, loser, loserPath[0], _sendTime(50));
        _finishLane(roundId, winner);

        assertEq(controller.getRoundWinner(roundId), winner);

        // Loser finishing later becomes runner-up, never winner.
        vm.prank(executor);
        controller.recordHop(roundId, loser, loserPath[1], _sendTime(50));
        assertEq(controller.getRoundWinner(roundId), winner);
        assertEq(controller.getRoundRunnerUp(roundId), loser);
    }

    // ---------------------------------------------------------------- security

    function test_onReport_disallowedSelector_reverts() public {
        vm.prank(cre);
        bytes memory report = abi.encodeWithSignature("pause()");
        vm.expectRevert();
        controller.onReport("", report);
    }

    function test_onReport_respectsPause() public {
        uint256 roundId = _createRound();
        // Step past the round-creation cooldown so only the pause gates the report.
        vm.warp(block.timestamp + controller.roundCooldown());
        controller.pause();

        uint64[][] memory paths = _twoLanePaths();
        bytes memory report = abi.encodeWithSelector(
            LaneController.createRound.selector, paths
        );
        vm.prank(cre);
        vm.expectRevert();
        controller.onReport("", report);

        controller.unpause();
        vm.prank(cre);
        controller.onReport("", report);
        assertEq(controller.currentRoundId(), roundId + 1);
    }

    function test_recordHop_futureSendTime_reverts() public {
        uint256 roundId = _createRound();
        vm.prank(cre);
        controller.startRace(roundId);

        vm.prank(executor);
        vm.expectRevert(LaneController.InvalidSendTime.selector);
        controller.recordHop(roundId, 0, SEPOLIA, block.timestamp + 1);
    }

    function test_recordHop_wrongChainForHopIndex_reverts() public {
        uint256 roundId = _createRound();
        vm.prank(cre);
        controller.startRace(roundId);

        // Lane 0 path is [SEPOLIA, ARBITRUM]: hop 0 must be SEPOLIA.
        vm.prank(executor);
        vm.expectRevert(LaneController.InvalidChainSelector.selector);
        controller.recordHop(roundId, 0, ARBITRUM, _sendTime(10));

        // Correct chain for hop 0 is accepted, then hop 1 must be ARBITRUM.
        vm.startPrank(executor);
        controller.recordHop(roundId, 0, SEPOLIA, _sendTime(10));
        vm.expectRevert(LaneController.InvalidChainSelector.selector);
        controller.recordHop(roundId, 0, SEPOLIA, _sendTime(10));
        vm.stopPrank();
    }

    function test_claimPrize_worksWhilePaused() public {
        uint256 roundId = _createRound();
        vm.prank(player);
        controller.buyLaneTokens(roundId, 0, 100e6);

        vm.prank(cre);
        controller.startRace(roundId);
        _finishLane(roundId, 0);
        vm.prank(cre);
        controller.distributePrizes(roundId);

        controller.pause();

        PrizeCalculator.Payout memory p = PrizeCalculator.calculate(100e6);
        vm.prank(player);
        assertEq(controller.claimPrize(roundId), p.winner);
    }

    // ---------------------------------------------------------------- rate limiting

    function test_roundCooldown_blocksBackToBackCreation() public {
        assertEq(controller.roundCooldown(), controller.DEFAULT_ROUND_COOLDOWN());

        uint256 createdAt = block.timestamp;
        _createRound();
        assertEq(controller.lastRoundCreatedAt(), createdAt);

        uint256 availableAt = createdAt + controller.roundCooldown();
        vm.prank(cre);
        vm.expectRevert(abi.encodeWithSelector(LaneController.RoundCooldownActive.selector, availableAt));
        controller.createRound(_twoLanePaths());

        // Still blocked one second before expiry, allowed at expiry.
        vm.warp(availableAt - 1);
        vm.prank(cre);
        vm.expectRevert(abi.encodeWithSelector(LaneController.RoundCooldownActive.selector, availableAt));
        controller.createRound(_twoLanePaths());

        vm.warp(availableAt);
        assertEq(_createRound(), 2);
    }

    function test_roundCooldown_appliesToOwnerToo() public {
        uint256 availableAt = block.timestamp + controller.roundCooldown();
        _createRound();

        vm.expectRevert(abi.encodeWithSelector(LaneController.RoundCooldownActive.selector, availableAt));
        controller.createRound(_twoLanePaths());
    }

    function test_roundCooldown_blocksCreateRoundViaReport() public {
        _createRound();

        bytes memory report = abi.encodeWithSelector(LaneController.createRound.selector, _twoLanePaths());
        vm.prank(cre);
        vm.expectRevert(LaneController.ReportExecutionFailed.selector);
        controller.onReport("", report);
    }

    function test_setRoundCooldown_ownerConfigurable() public {
        vm.prank(player);
        vm.expectRevert();
        controller.setRoundCooldown(120);

        vm.expectEmit(false, false, false, true);
        emit RoundCooldownUpdated(120);
        controller.setRoundCooldown(120);
        assertEq(controller.roundCooldown(), 120);

        uint256 availableAt = block.timestamp + 120;
        _createRound();
        vm.warp(availableAt - 1);
        vm.prank(cre);
        vm.expectRevert(abi.encodeWithSelector(LaneController.RoundCooldownActive.selector, availableAt));
        controller.createRound(_twoLanePaths());
    }

    function test_setRoundCooldown_zeroDisablesGuard() public {
        controller.setRoundCooldown(0);
        assertEq(_createRound(), 1);
        assertEq(_createRound(), 2);
    }

    function test_sweepUnclaimed_afterSettlement() public {
        uint256 roundId = _createRound();
        vm.prank(player);
        controller.buyLaneTokens(roundId, 0, 100e6);
        vm.prank(rival);
        controller.buyLaneTokens(roundId, 1, 300e6);

        vm.prank(cre);
        controller.startRace(roundId);
        _finishLane(roundId, 0);
        _finishLane(roundId, 1);
        vm.prank(cre);
        controller.distributePrizes(roundId);

        PrizeCalculator.Payout memory p = PrizeCalculator.calculate(400e6);
        uint256 treasuryBefore = token.balanceOf(treasury);

        vm.prank(cre);
        controller.sweepUnclaimed(roundId);

        assertEq(token.balanceOf(treasury), treasuryBefore + p.winner + p.runnerUp);
    }
}
