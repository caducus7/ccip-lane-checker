// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2 <0.9.0;

import "../Base.sol";
import {Properties} from "../Properties.sol";
import {LaneController} from "../../../src/core/LaneController.sol";

abstract contract LaneControllerHandler is Properties {
  enum AdminAction {
    Pause,
    Unpause,
    ZeroClaimWindow,
    ExtendClaimWindow,
    ZeroRunnerUpTimeout,
    ExtendRunnerUpTimeout
  }

  // ――――――――――――――――――――――――― Clamped ――――――――――――――――――――――――――

  function controller_createRound(uint256) public asCre {
    uint256 roundId = controller.createRound(_twoLanePaths());
    _trackRound(roundId);
  }

  function controller_buyLaneTokens(uint256 roundId, uint256 laneSeed, uint256 amount) public asActor {
    if (knownRoundIds.length == 0) return;
    roundId = knownRoundIds[roundId % knownRoundIds.length];
    if (controller.getRoundState(roundId) != LaneController.RoundState.Betting) return;
    uint8 laneId = uint8(laneSeed % 2);
        amount = clampBetween(amount, controller.minBet(), bettingToken.balanceOf(actor) / 10);
    if (amount == 0) return;
    uint256 poolBefore = controller.getLanePool(roundId, laneId);
    controller.buyLaneTokens(roundId, laneId, amount);
    ghosts.controllerDeposits += amount;
    t(controller.getLanePool(roundId, laneId) == poolBefore + amount, "lane pool increase");
  }

  function controller_startRace(uint256 roundId) public asCre {
    if (knownRoundIds.length == 0) return;
    roundId = knownRoundIds[roundId % knownRoundIds.length];
    controller.startRace(roundId);
  }

  function controller_recordHop(uint256 roundId, uint256 laneSeed, uint256 timeSkew) public asExecutor {
    if (knownRoundIds.length == 0) return;
    roundId = knownRoundIds[roundId % knownRoundIds.length];
  LaneController.RoundState state = controller.getRoundState(roundId);
    if (state != LaneController.RoundState.Racing && state != LaneController.RoundState.Finished) return;
    uint8 laneId = uint8(laneSeed % 2);
    (uint64[] memory path,,,,,) = controller.getLane(roundId, laneId);
    if (path.length == 0) return;
    uint64 chain = path[0];
    uint256 sendTime = block.timestamp > timeSkew % 600 ? block.timestamp - (timeSkew % 600) : block.timestamp;
    controller.recordHop(roundId, laneId, chain, sendTime);
  }

  function controller_finishBothLanes(uint256 roundId) public asExecutor {
    if (knownRoundIds.length == 0) return;
    roundId = knownRoundIds[roundId % knownRoundIds.length];
    controller.recordHop(roundId, 0, HOP_CHAIN_A, block.timestamp - 30);
    controller.recordHop(roundId, 1, HOP_CHAIN_B, block.timestamp - 20);
  }

  function controller_distributePrizes(uint256 roundId) public asCre {
    if (knownRoundIds.length == 0) return;
    roundId = knownRoundIds[roundId % knownRoundIds.length];
    try controller.distributePrizes(roundId) {
      if (controller.getRoundState(roundId) == LaneController.RoundState.Settled) {
        _recordSettlementShares(roundId);
      }
    } catch {}
  }

  function controller_claimPrize(uint256 roundId) public asActor {
    if (knownRoundIds.length == 0) return;
    roundId = knownRoundIds[roundId % knownRoundIds.length];
    if (controller.getRoundState(roundId) != LaneController.RoundState.Settled) return;
    uint256 balBefore = bettingToken.balanceOf(actor);
    try controller.claimPrize(roundId) returns (uint256 claimed) {
      ghosts.controllerPayouts += claimed;
      ghostTotalClaimed[roundId] += claimed;
      uint8 winnerLane = controller.getRoundWinner(roundId);
      uint8 runnerUpLane = controller.getRoundRunnerUp(roundId);
      if (controller.getBet(roundId, winnerLane, actor) > 0) {
        ghostWinnerClaimed[roundId] += claimed;
      } else if (runnerUpLane != type(uint8).max && controller.getBet(roundId, runnerUpLane, actor) > 0) {
        ghostRunnerUpClaimed[roundId] += claimed;
      }
      t(bettingToken.balanceOf(actor) == balBefore + claimed, "claim payout");
    } catch {}
  }

  function controller_sweepUnclaimed(uint256 roundId) public asCre {
    if (knownRoundIds.length == 0) return;
    roundId = knownRoundIds[roundId % knownRoundIds.length];
    skipTime(8 days);
    try controller.sweepUnclaimed(roundId) {
      ghostTotalClaimed[roundId] = ghostWinnerShare[roundId] + ghostRunnerUpShare[roundId];
      ghostWinnerClaimed[roundId] = ghostWinnerShare[roundId];
      ghostRunnerUpClaimed[roundId] = ghostRunnerUpShare[roundId];
    } catch {}
  }

  function controller_adminDispatch(uint256 actionSeed) public asAdmin {
    AdminAction action = AdminAction(actionSeed % 6);
    if (action == AdminAction.Pause) controller.pause();
    else if (action == AdminAction.Unpause) controller.unpause();
    else if (action == AdminAction.ZeroClaimWindow) controller.setClaimWindow(0);
    else if (action == AdminAction.ExtendClaimWindow) controller.setClaimWindow(14 days);
    else if (action == AdminAction.ZeroRunnerUpTimeout) controller.setRunnerUpSettlementTimeout(0);
    else controller.setRunnerUpSettlementTimeout(14 days);
  }

  // ―――――――――――――――――――――――― Unclamped ―――――――――――――――――――――――――

  function controller_buyLaneTokens_raw(uint256 roundId, uint8 laneId, uint256 amount) public asActor {
    controller.buyLaneTokens(roundId, laneId, amount);
    ghosts.controllerDeposits += amount;
  }

  function controller_recordHop_raw(uint256 roundId, uint8 laneId, uint64 chain, uint256 sendTime) public asExecutor {
    controller.recordHop(roundId, laneId, chain, sendTime);
  }
}
