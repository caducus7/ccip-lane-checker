// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2 <0.9.0;

import "../Base.sol";
import {LaneControllerHandler} from "./LaneControllerHandler.sol";
import {LaneExecutorHandler} from "./LaneExecutorHandler.sol";
import {LaneTokenHandler} from "./LaneTokenHandler.sol";

abstract contract Handlers is LaneControllerHandler, LaneExecutorHandler, LaneTokenHandler {
    function setCurrentActor(uint256 entropy) public {
        actor = actors[entropy % actors.length];
    }
}
