// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2 <0.9.0;

import "../Base.sol";
import {Properties} from "../Properties.sol";
import {LaneController} from "../../../src/core/LaneController.sol";
import {LaneExecutor} from "../../../src/core/LaneExecutor.sol";
import {LaneToken} from "../../../src/core/LaneToken.sol";

/// @notice Handlers targeting uncovered protocol paths for Medusa line coverage.
abstract contract CoverageHandlers is Properties {
    // ――――――――――――――――――――――――― LaneController ―――――――――――――――――――――――――

    function coverage_controller_createMultiHopRound() public asCre {
        uint256 cur = controller.currentRoundId();
        if (cur > 0) {
            LaneController.RoundState s = controller.getRoundState(cur);
            if (
                s == LaneController.RoundState.Betting || s == LaneController.RoundState.Racing
                    || s == LaneController.RoundState.Finished
            ) return;
        }
        uint256 roundId = controller.createRound(_threeLanePaths());
        _trackRound(roundId);
    }

    function coverage_controller_recordHopAlongPath(uint256 roundId, uint256 laneSeed) public asExecutor {
        if (knownRoundIds.length == 0) return;
        roundId = knownRoundIds[roundId % knownRoundIds.length];
        uint8 laneId = uint8(laneSeed % 2);
        (uint64[] memory path, uint8 hopsCompleted,,,,) = controller.getLane(roundId, laneId);
        if (path.length == 0 || hopsCompleted >= path.length) return;
        LaneController.RoundState state = controller.getRoundState(roundId);
        if (state != LaneController.RoundState.Racing && state != LaneController.RoundState.Finished) return;
        uint64 chain = path[hopsCompleted];
        controller.recordHop(roundId, laneId, chain, block.timestamp - 30);
    }

    function coverage_controller_declareWinner(uint256 roundId, uint256 laneSeed) public asCre {
        if (knownRoundIds.length == 0) return;
        roundId = knownRoundIds[roundId % knownRoundIds.length];
        uint8 laneId = uint8(laneSeed % 2);
        _forceFinishLaneWithoutWinner(roundId, laneId);
        try controller.declareWinner(roundId, laneId) {} catch {}
    }

    function coverage_controller_onReportDistribute(uint256 roundId) public {
        if (knownRoundIds.length == 0) return;
        roundId = knownRoundIds[roundId % knownRoundIds.length];
        bytes memory report = abi.encodeWithSelector(LaneController.distributePrizes.selector, roundId);
        vm.prank(cre);
        try controller.onReport("", report) {
            if (controller.getRoundState(roundId) == LaneController.RoundState.Settled) {
                _recordSettlementShares(roundId);
            }
        } catch {}
    }

    function coverage_controller_onReportSweep(uint256 roundId) public {
        if (knownRoundIds.length == 0) return;
        roundId = knownRoundIds[roundId % knownRoundIds.length];
        skipTime(8 days);
        bytes memory report = abi.encodeWithSelector(LaneController.sweepUnclaimed.selector, roundId);
        vm.prank(cre);
        try controller.onReport("", report) {
            ghostTotalClaimed[roundId] = ghostWinnerShare[roundId] + ghostRunnerUpShare[roundId];
            ghostWinnerClaimed[roundId] = ghostWinnerShare[roundId];
            ghostRunnerUpClaimed[roundId] = ghostRunnerUpShare[roundId];
        } catch {}
    }

    function coverage_controller_onReportCreateRound() public {
        bytes memory report = abi.encodeWithSelector(LaneController.createRound.selector, _twoLanePaths());
        vm.prank(cre);
        try controller.onReport("", report) {
            _trackRound(controller.currentRoundId());
        } catch {}
    }

    function coverage_controller_setMinBet(uint256 amount) public asAdmin {
        amount = clampBetween(amount, 1, 1000e6);
        controller.setMinBet(amount);
    }

    function coverage_controller_setCreForwarder(address forwarder) public asAdmin {
        if (forwarder == address(0)) return;
        controller.setCreForwarder(forwarder);
    }

    function coverage_controller_rotateHopRecorder(uint256 seed) public asAdmin {
        address alt = seed % 2 == 0 ? address(spokeExecutor) : address(executor);
        controller.setHopRecorder(alt, true);
        if (seed % 3 == 0) {
            controller.setHopRecorder(alt, false);
        }
        controller.setHopRecorder(address(executor), true);
    }

    function coverage_controller_touchViews() public view {
        controller.bettingToken();
        controller.creForwarder();
        controller.platformTreasury();
        controller.gasReserve();
        controller.currentRoundId();
        controller.primaryHopRecorder();
        controller.roundCooldown();
        controller.lastRoundCreatedAt();
        controller.minBet();
        controller.claimWindow();
        controller.runnerUpSettlementTimeout();
        controller.DEFAULT_ROUND_COOLDOWN();
        controller.DEFAULT_CLAIM_WINDOW();
        controller.DEFAULT_RUNNER_UP_SETTLEMENT_TIMEOUT();
        controller.DEFAULT_MIN_BET();
    }

    // ――――――――――――――――――――――――― LaneExecutor ―――――――――――――――――――――――――

    function coverage_executor_setCreForwarder(address forwarder) public asAdmin {
        if (forwarder == address(0)) return;
        executor.setCreForwarder(forwarder);
        spokeExecutor.setCreForwarder(forwarder);
    }

    function coverage_executor_onReportSendHop(uint256 roundId, uint8 laneId, uint64 hopChain) public {
        bytes memory report = abi.encodeWithSelector(LaneExecutor.sendHop.selector, roundId, laneId, hopChain);
        vm.prank(cre);
        try executor.onReport("", report) {} catch {}
    }

    function coverage_executor_spokeRelayRace(uint256 roundId) public {
        if (knownRoundIds.length == 0) return;
        roundId = knownRoundIds[roundId % knownRoundIds.length];

        vm.startPrank(cre);
        try executor.sendHop(roundId, 0, HOP_CHAIN_A) {} catch {}
        vm.stopPrank();

        vm.startPrank(cre);
        try executor.sendHop(roundId, 1, HOP_CHAIN_B) {} catch {}
        vm.stopPrank();
    }

    function coverage_executor_touchViews() public view {
        executor.laneController();
        executor.creForwarder();
        executor.localChainSelector();
        executor.homeChainSelector();
        executor.canonicalController();
        executor.homeExecutor();
    }

    // ――――――――――――――――――――――――― LaneToken ―――――――――――――――――――――――――

    function coverage_laneToken_adminOps(uint256 seed) public {
        if (seed % 2 == 0) {
            laneToken.setRemoteLaneToken(SOLO_CHAIN_SELECTOR, address(laneToken));
        }
        if (seed % 3 == 0) {
            address tmp = actors[seed % actors.length];
            laneToken.transferAdmin(tmp);
            vm.prank(tmp);
            laneToken.acceptAdmin();
            vm.prank(tmp);
            laneToken.acceptOwnership();
            vm.prank(tmp);
            laneToken.transferAdmin(admin);
            vm.prank(admin);
            laneToken.acceptAdmin();
            vm.prank(admin);
            laneToken.acceptOwnership();
        }
    }

    function coverage_laneToken_finishCrossChainOnRemote() public asActor {
        uint256 amount = clampBetween(15e6, 1, bettingToken.balanceOf(actor));
        if (amount == 0) return;
        originLaneToken.deposit(amount);
        ghosts.laneTokenDeposits += amount;
        originLaneToken.startGame(REMOTE_SELECTOR, amount, 1);
        lastCrossChainGameId = originLaneToken.s_gameCounter();
    }

    function coverage_laneToken_abandonStuckLocal() public asActor {
        uint256 amount = clampBetween(10e6, 1, bettingToken.balanceOf(actor));
        if (amount == 0) return;
        laneToken.deposit(amount);
        ghosts.laneTokenDeposits += amount;
        laneToken.startGame(SOLO_CHAIN_SELECTOR, amount, 3);
        lastSoloGameId = laneToken.s_gameCounter();
        skipTime(8 days);
        try laneToken.abandonGame(lastSoloGameId) {} catch {}
    }

    function coverage_laneToken_touchGameRound(uint256 gameSeed) public view {
        uint256 gameId = gameSeed % (laneToken.s_gameCounter() + 1);
        if (gameId == 0) gameId = 1;
        laneToken.getGameRound(gameId);
        originLaneToken.getGameRound(gameId);
        remoteLaneToken.getGameRound(gameId);
    }

    function coverage_creReportAuth_validReports(uint256 roundId) public {
        bytes memory createReport = abi.encodeWithSelector(LaneController.createRound.selector, _twoLanePaths());
        vm.prank(cre);
        try controller.onReport("", createReport) {
            _trackRound(controller.currentRoundId());
        } catch {}

        bytes memory hopReport = abi.encodeWithSelector(LaneExecutor.sendHop.selector, roundId, uint8(0), HOP_CHAIN_A);
        vm.prank(cre);
        try executor.onReport("", hopReport) {
            if (execRouterDelivers) ghosts.executorHopsDelivered++;
        } catch {}
    }

    function coverage_creReportAuth_invalidReports() public {
        vm.prank(cre);
        try controller.onReport("", hex"") {} catch {}
        vm.prank(cre);
        try controller.onReport("", abi.encodeWithSelector(bytes4(0xdeadbeef), uint256(1))) {} catch {}
        vm.prank(cre);
        try executor.onReport("", hex"") {} catch {}
        vm.prank(cre);
        try executor.onReport("", abi.encodeWithSelector(bytes4(0xdeadbeef), uint256(1))) {} catch {}
    }

    function coverage_controller_dualShareClaim() public {
        uint256 cur = controller.currentRoundId();
        if (cur > 0) {
            LaneController.RoundState s = controller.getRoundState(cur);
            if (
                s == LaneController.RoundState.Betting || s == LaneController.RoundState.Racing
                    || s == LaneController.RoundState.Finished
            ) return;
        }
        vm.prank(cre);
        uint256 roundId = controller.createRound(_twoLanePaths());
        _trackRound(roundId);
        actor = actors[0];
        vm.startPrank(actor);
        controller.buyLaneTokens(roundId, 1, 200e6);
        vm.stopPrank();
        vm.prank(cre);
        controller.startRace(roundId);
        vm.startPrank(address(executor));
        controller.recordHop(roundId, 0, HOP_CHAIN_A, block.timestamp - 30);
        controller.recordHop(roundId, 1, HOP_CHAIN_B, block.timestamp - 20);
        vm.stopPrank();
        coverage_controller_onReportDistribute(roundId);
        vm.prank(actor);
        try controller.claimPrize(roundId) returns (uint256 claimed) {
            ghosts.controllerPayouts += claimed;
            ghostTotalClaimed[roundId] += claimed;
        } catch {}
    }

    function coverage_executor_unauthorizedSend(uint256 roundId, uint8 laneId, uint64 hopChain) public asActor {
        try executor.sendHop(roundId, laneId, hopChain) {} catch {}
    }

    function coverage_laneToken_unwiredStart(uint64 selector, uint256 amount) public asActor {
        amount = clampBetween(amount, 1, laneToken.s_balances(actor));
        if (amount == 0) return;
        try laneToken.startGame(selector, amount, 1) {} catch {}
    }

    /// @notice Single entry the fuzzer can discover to exercise most uncovered paths.
    function coverage_runAll(uint256 seed) public {
        coverage_controller_touchViews();
        coverage_executor_touchViews();
        coverage_laneToken_touchGameRound(seed);
        coverage_creReportAuth_invalidReports();
        coverage_creReportAuth_validReports(seed % 10 + 1);
        coverage_controller_setMinBet(1e6);
        coverage_controller_setCreForwarder(cre);
        coverage_controller_rotateHopRecorder(seed);
        coverage_controller_createMultiHopRound();
        coverage_controller_onReportCreateRound();
        coverage_executor_setCreForwarder(cre);
        coverage_executor_onReportSendHop(seed % 10 + 1, uint8(seed % 2), HOP_CHAIN_A);
        coverage_executor_spokeRelayRace(seed % 10 + 1);
        coverage_laneToken_adminOps(seed);
        coverage_laneToken_finishCrossChainOnRemote();
        coverage_laneToken_abandonStuckLocal();
        coverage_controller_dualShareClaim();
        coverage_executor_unauthorizedSend(uint8(seed % 10 + 1), uint8(seed % 2), HOP_CHAIN_A);
        coverage_laneToken_unwiredStart(uint64(seed), 5e6);
        if (knownRoundIds.length > 0) {
            uint256 roundId = knownRoundIds[seed % knownRoundIds.length];
            coverage_controller_recordHopAlongPath(roundId, seed);
            coverage_controller_declareWinner(roundId, seed);
            coverage_controller_onReportDistribute(roundId);
            coverage_controller_onReportSweep(roundId);
        }
    }
}
