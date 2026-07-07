// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2 <0.9.0;

import {Snapshots} from "./Snapshots.sol";
import {PropertiesAsserts} from "./utils/PropertiesAsserts.sol";
import {LaneController} from "../../src/core/LaneController.sol";
import {PrizeCalculator} from "../../src/libraries/PrizeCalculator.sol";

abstract contract Properties is PropertiesAsserts, Snapshots {
    mapping(uint256 => uint256) internal ghostWinnerClaimed;
    mapping(uint256 => uint256) internal ghostRunnerUpClaimed;
    mapping(uint256 => uint256) internal ghostWinnerShare;
    mapping(uint256 => uint256) internal ghostRunnerUpShare;
    mapping(uint256 => uint256) internal ghostTotalClaimed;

    function property_controllerTokenSolvency() public view returns (bool) {
        return bettingToken.balanceOf(address(controller)) >= _controllerOutstanding();
    }

    function property_laneTokenBookedSolvency() public view returns (bool) {
        return _laneTokenSolvent(laneToken);
    }

    function property_originLaneTokenSolvency() public view returns (bool) {
        return _laneTokenSolvent(originLaneToken);
    }

    function property_remoteLaneTokenSolvency() public view returns (bool) {
        return _laneTokenSolvent(remoteLaneToken);
    }

    function property_allLaneTokensSolvent() public view returns (bool) {
        return property_laneTokenBookedSolvency() && property_originLaneTokenSolvency()
            && property_remoteLaneTokenSolvency();
    }

    function property_executorWired() public view returns (bool) {
        return executor.remoteExecutors(HOP_CHAIN_A) != address(0)
            && executor.remoteExecutors(HOP_CHAIN_B) != address(0)
            && controller.hopRecorders(address(executor));
    }

    function property_prizeShareConservation() public view returns (bool) {
        for (uint256 i; i < knownRoundIds.length; i++) {
            uint256 roundId = knownRoundIds[i];
            if (controller.getRoundState(roundId) != LaneController.RoundState.Settled) continue;
            if (ghostTotalClaimed[roundId] > ghostWinnerShare[roundId] + ghostRunnerUpShare[roundId]) {
                return false;
            }
            if (ghostWinnerClaimed[roundId] > ghostWinnerShare[roundId]) return false;
            if (ghostRunnerUpClaimed[roundId] > ghostRunnerUpShare[roundId]) return false;
        }
        return true;
    }

    function property_distributedPayoutMatchesCalculator() public view returns (bool) {
        for (uint256 i; i < knownRoundIds.length; i++) {
            uint256 roundId = knownRoundIds[i];
            if (controller.getRoundState(roundId) != LaneController.RoundState.Settled) continue;
            uint256 pool = controller.getTotalPrizePool(roundId);
            PrizeCalculator.Payout memory p = PrizeCalculator.calculate(pool);
            uint8 winningLaneId = controller.getRoundWinner(roundId);
            uint8 runnerUpLaneId = controller.getRoundRunnerUp(roundId);
            uint8 payoutLaneId = _winnerPayoutLane(roundId, winningLaneId);

            uint256 expectedWinner;
            if (payoutLaneId != type(uint8).max && controller.getLanePool(roundId, payoutLaneId) > 0) {
                expectedWinner = p.winner;
            }
            uint256 expectedRunnerUp;
            if (runnerUpLaneId != type(uint8).max && controller.getLanePool(roundId, runnerUpLaneId) > 0) {
                expectedRunnerUp = p.runnerUp;
            }

            if (ghostWinnerShare[roundId] != expectedWinner || ghostRunnerUpShare[roundId] != expectedRunnerUp) {
                return false;
            }
        }
        return true;
    }

    function _controllerOutstanding() internal view returns (uint256 outstanding) {
        uint256 maxRound = controller.currentRoundId();
        for (uint256 i; i < knownRoundIds.length; i++) {
            uint256 roundId = knownRoundIds[i];
            if (roundId == 0 || roundId > maxRound) continue;
            LaneController.RoundState state = controller.getRoundState(roundId);
            if (state == LaneController.RoundState.Settled) {
                uint256 allocated = ghostWinnerShare[roundId] + ghostRunnerUpShare[roundId];
                if (allocated > ghostTotalClaimed[roundId]) {
                    outstanding += allocated - ghostTotalClaimed[roundId];
                }
            } else if (state == LaneController.RoundState.Betting || state == LaneController.RoundState.Racing
                || state == LaneController.RoundState.Finished) {
                outstanding += controller.getLanePool(roundId, 0);
                outstanding += controller.getLanePool(roundId, 1);
            }
        }
    }

    function _recordSettlementShares(uint256 roundId) internal {
        uint256 pool = controller.getTotalPrizePool(roundId);
        PrizeCalculator.Payout memory p = PrizeCalculator.calculate(pool);

        uint8 winningLaneId = controller.getRoundWinner(roundId);
        uint8 runnerUpLaneId = controller.getRoundRunnerUp(roundId);
        uint8 payoutLaneId = _winnerPayoutLane(roundId, winningLaneId);

        uint256 winnerShare;
        if (payoutLaneId != type(uint8).max && controller.getLanePool(roundId, payoutLaneId) >= controller.minBet()) {
            winnerShare = p.winner;
        }

        uint256 runnerUpShare;
        if (runnerUpLaneId != type(uint8).max && controller.getLanePool(roundId, runnerUpLaneId) >= controller.minBet()) {
            runnerUpShare = p.runnerUp;
        }

        ghostWinnerShare[roundId] = winnerShare;
        ghostRunnerUpShare[roundId] = runnerUpShare;
    }

    function _winnerPayoutLane(uint256 roundId, uint8 winningLaneId) internal view returns (uint8) {
        if (controller.getLanePool(roundId, winningLaneId) >= controller.minBet()) return winningLaneId;

        uint8 bestLane = type(uint8).max;
        uint256 bestPool;
        for (uint8 i = 0; i < 2; i++) {
            if (i == winningLaneId) continue;
            uint256 pool = controller.getLanePool(roundId, i);
            if (pool >= controller.minBet() && pool > bestPool) {
                bestPool = pool;
                bestLane = i;
            }
        }
        return bestLane;
    }
}
