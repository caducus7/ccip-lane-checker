// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2 <0.9.0;

import "../Base.sol";
import {Properties} from "../Properties.sol";
import {LaneExecutor} from "../../../src/core/LaneExecutor.sol";

abstract contract LaneExecutorHandler is Properties {
    enum ExecAdminAction {
        Pause,
        Unpause,
        ToggleHopSender
    }

    // ――――――――――――――――――――――――― Clamped ――――――――――――――――――――――――――

    function executor_sendHopAndDeliver(uint256 roundId, uint256 laneSeed, uint256 chainSeed) public {
        if (knownRoundIds.length == 0) return;
        roundId = knownRoundIds[roundId % knownRoundIds.length];
        uint8 laneId = uint8(laneSeed % 2);
        uint64 hopChain = chainSeed % 2 == 0 ? HOP_CHAIN_A : HOP_CHAIN_B;
        uint256 sendTime = block.timestamp - (chainSeed % 120);

        vm.startPrank(cre);
        try executor.sendHop(roundId, laneId, hopChain) {
            if (execRouterDelivers) ghosts.executorHopsDelivered++;
        } catch {}
        vm.stopPrank();
        if (!execRouterDelivers) {
            _deliverExecutorHop(roundId, laneId, hopChain, sendTime);
        }
    }

    function executor_finishRaceViaCcip(uint256 roundId) public {
        if (knownRoundIds.length == 0) return;
        roundId = knownRoundIds[roundId % knownRoundIds.length];

        vm.startPrank(cre);
        try executor.sendHop(roundId, 0, HOP_CHAIN_A) {
            if (execRouterDelivers) ghosts.executorHopsDelivered++;
        } catch {}
        vm.stopPrank();
        if (!execRouterDelivers) {
            _deliverExecutorHop(roundId, 0, HOP_CHAIN_A, block.timestamp - 60);
        }

        vm.startPrank(cre);
        try executor.sendHop(roundId, 1, HOP_CHAIN_B) {
            if (execRouterDelivers) ghosts.executorHopsDelivered++;
        } catch {}
        vm.stopPrank();
        if (!execRouterDelivers) {
            _deliverExecutorHop(roundId, 1, HOP_CHAIN_B, block.timestamp - 30);
        }
    }

    function executor_adminDispatch(uint256 actionSeed) public asAdmin {
        ExecAdminAction action = ExecAdminAction(actionSeed % 3);
        if (action == ExecAdminAction.Pause) executor.pause();
        else if (action == ExecAdminAction.Unpause) executor.unpause();
        else executor.setHopSender(cre, actionSeed % 2 == 0);
    }

    // ―――――――――――――――――――――――― Unclamped ―――――――――――――――――――――――――

    function executor_sendHop_raw(uint256 roundId, uint8 laneId, uint64 hopChain) public asCre {
        executor.sendHop(roundId, laneId, hopChain);
    }

    function executor_deliverHop_raw(uint256 roundId, uint8 laneId, uint64 hopChain, uint256 sendTime) public {
        _deliverExecutorHop(roundId, laneId, hopChain, sendTime);
    }
}
