// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2 <0.9.0;

import {Test} from "forge-std/Test.sol";
import {Handlers} from "./handlers/Handlers.sol";
import {LaneController} from "../../src/core/LaneController.sol";

contract FoundryTester is Test, Handlers {
    modifier asActor() override {
        vm.startPrank(actor);
        _;
        vm.stopPrank();
    }

    function setUp() public {
        setup();
    }

    function test_parimutuelLifecycle_propertiesHold() public {
        actor = actors[0];
        controller_createRound(0);
        controller_buyLaneTokens(0, 0, 100e6);
        actor = actors[1];
        controller_buyLaneTokens(0, 1, 200e6);
        controller_startRace(0);
        controller_finishBothLanes(0);
        controller_distributePrizes(0);
        assertTrue(property_controllerTokenSolvency());
        assertTrue(property_prizeShareConservation());
        assertTrue(property_distributedPayoutMatchesCalculator());
    }

    function test_executorCcipRace_propertiesHold() public {
        assertTrue(property_executorWired());
        actor = actors[0];
        controller_createRound(0);
        controller_buyLaneTokens(0, 0, 100e6);
        actor = actors[1];
        controller_buyLaneTokens(0, 1, 200e6);
        controller_startRace(0);
        executor_finishRaceViaCcip(0);
        controller_distributePrizes(0);
        assertTrue(property_controllerTokenSolvency());
        assertGt(ghosts.executorHopsDelivered, 0);
    }

    function test_laneTokenDepositWithdraw_propertyHolds() public {
        actor = actors[0];
        laneToken_deposit(50e6);
        laneToken_withdraw(10e6);
        assertTrue(property_laneTokenBookedSolvency());
        assertTrue(property_allLaneTokensSolvent());
    }

    function test_crossChainReturnHop_reactivatesOrigin() public {
        actor = actors[0];
        origin_deposit(50e6);
        origin_startCrossChainGame(20e6, 3);

        assertEq(originLaneToken.s_tokensInPlay(), 0);
        (,,, uint8 remoteHops,,, bool remoteActive) = remoteLaneToken.getGameRound(1);
        assertEq(remoteHops, 1);
        assertTrue(remoteActive);

        remote_fulfillVrfReturnToOrigin(1);

        (,,, uint8 originHops,,, bool originActive) = originLaneToken.getGameRound(1);
        assertEq(originHops, 1);
        assertTrue(originActive);
        assertEq(originLaneToken.s_tokensInPlay(), 20e6);
        assertTrue(property_originLaneTokenSolvency());
        assertTrue(property_remoteLaneTokenSolvency());
    }

    function test_singleLaneBet_settlementSolvency() public {
        actor = actors[0];
        controller_createRound(0);
        controller_buyLaneTokens(0, 0, 50e6);
        controller_startRace(0);
        controller_finishBothLanes(0);
        controller_distributePrizes(0);
        assertTrue(property_controllerTokenSolvency());
    }

    function test_claimAfterSettle_solvencyHolds() public {
        actor = actors[0];
        controller_createRound(0);
        controller_buyLaneTokens(0, 0, 80e6);
        controller_startRace(0);
        controller_finishBothLanes(0);
        controller_distributePrizes(0);
        controller_claimPrize(0);
        assertTrue(property_controllerTokenSolvency());
    }

    function test_spokeRelayRace_propertiesHold() public {
        actor = actors[0];
        controller_createRound(0);
        controller_buyLaneTokens(0, 0, 100e6);
        controller_startRace(0);
        executor_finishRaceViaCcip(0);
        assertTrue(property_controllerTokenSolvency());
        assertGt(ghosts.executorHopsDelivered, 0);
        assertEq(uint256(controller.getRoundState(1)), uint256(LaneController.RoundState.Finished));
    }

    function test_coverageRunAll_propertiesHold() public {
        coverage_runAll(42);
        assertTrue(property_allLaneTokensSolvent());
        assertTrue(property_controllerTokenSolvency());
    }
}
