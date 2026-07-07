// SPDX-License-Identifier: LicenseRef-Caducus-Commercial
pragma solidity ^0.8.24;

import {Pausable as OZPausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title LaneControllerPausable
/// @notice Emergency pause mixin for `LaneController` (Step 7 hardening).
/// @dev Inherit in `LaneController` when Step 2 lands. Apply `whenNotPaused` to state-changing entrypoints:
///      `createRound`, `buyLaneTokens`, `startRace`, `declareWinner`, `distributePrizes`.
abstract contract LaneControllerPausable is OZPausable, Ownable {
    constructor(address initialOwner) Ownable(initialOwner) {}

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
