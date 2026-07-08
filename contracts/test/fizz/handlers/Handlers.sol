// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2 <0.9.0;

import "../Base.sol";
import {CoverageHandlers} from "./CoverageHandlers.sol";
import {LaneControllerHandler} from "./LaneControllerHandler.sol";
import {LaneExecutorHandler} from "./LaneExecutorHandler.sol";
import {LaneTokenHandler} from "./LaneTokenHandler.sol";

abstract contract Handlers is LaneControllerHandler, LaneExecutorHandler, LaneTokenHandler, CoverageHandlers {
    function setCurrentActor(uint256 entropy) public {
        actor = actors[entropy % actors.length];
    }

    function _seedCoverage() internal {
        coverage_controller_touchViews();
        coverage_executor_touchViews();
        coverage_laneToken_touchGameRound(1);
        coverage_creReportAuth_invalidReports();

        controller.setMinBet(1e6);
        address creAlt = address(0xC0E00000000000000000000000000000000002);
        executor.setCreForwarder(creAlt);
        executor.setCreForwarder(cre);
        controller.setCreForwarder(creAlt);
        controller.setCreForwarder(cre);

        vm.prank(cre);
        uint256 roundId = controller.createRound(_twoLanePaths());
        _trackRound(roundId);
        actor = actors[0];
        vm.startPrank(actor);
        controller.buyLaneTokens(roundId, 0, 50e6);
        vm.stopPrank();
        vm.prank(cre);
        controller.startRace(roundId);
        executor_finishRaceViaCcip(roundId);
        coverage_controller_onReportDistribute(roundId);
        coverage_controller_declareWinner(roundId, 0);
        coverage_controller_createMultiHopRound();
        coverage_laneToken_finishCrossChainOnRemote();
        coverage_laneToken_abandonStuckLocal();
    }
}
