// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2 <0.9.0;

import {Base} from "./Base.sol";

abstract contract Snapshots is Base {
    struct State {
        uint256 controllerTokenBalance;
        uint256 laneTokenUnderlying;
        uint256 actorTokenBalance;
    }

    State internal stateBefore;
    State internal stateAfter;

    function _takeSnapshot(State storage state) private {
        state.controllerTokenBalance = bettingToken.balanceOf(address(controller));
        state.laneTokenUnderlying = bettingToken.balanceOf(address(laneToken));
        state.actorTokenBalance = bettingToken.balanceOf(actor);
    }

    function snapshotBefore() internal {
        _takeSnapshot(stateBefore);
    }

    function snapshotAfter() internal {
        _takeSnapshot(stateAfter);
    }
}
