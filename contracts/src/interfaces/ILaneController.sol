// SPDX-License-Identifier: LicenseRef-Caducus-Commercial
pragma solidity ^0.8.24;

interface ILaneController {
    function createRound(uint64[][] calldata lanePaths) external returns (uint256 roundId);
    function buyLaneTokens(uint256 roundId, uint8 laneId, uint256 amount) external;
    function startRace(uint256 roundId) external;
    function recordHop(uint256 roundId, uint8 laneId, uint64 chainSelector, uint256 sendTime) external;
    function declareWinner(uint256 roundId, uint8 laneId) external;
    function distributePrizes(uint256 roundId) external;
    function claimPrize(uint256 roundId) external returns (uint256 amount);
    function sweepUnclaimed(uint256 roundId) external;
    function abortRace(uint256 roundId) external;
    function claimRefund(uint256 roundId) external returns (uint256 amount);
    function isRaceAbortable(uint256 roundId) external view returns (bool);
    function currentRoundId() external view returns (uint256);
    function getRoundWinner(uint256 roundId) external view returns (uint8 winnerLaneId);
    function getRoundRunnerUp(uint256 roundId) external view returns (uint8 runnerUpLaneId);
    function getLanePool(uint256 roundId, uint8 laneId) external view returns (uint256);
    function getTotalPrizePool(uint256 roundId) external view returns (uint256);
    function getLane(uint256 roundId, uint8 laneId)
        external
        view
        returns (
            uint64[] memory chainPath,
            uint8 hopsCompleted,
            uint8 requiredHops,
            uint256 totalLatency,
            uint256 finishTime,
            bool finished
        );
}
