import { parseAbi } from "viem";

/**
 * Placeholder LaneController ABI — align with contracts/src/core/LaneController.sol.
 * CRE workflows ABI-encode function calls as report payloads for the IReceiver consumer.
 */
export const laneControllerAbi = parseAbi([
  "function createRound(uint64[][] lanePaths) external returns (uint256 roundId)",
  "function startRace(uint256 roundId) external",
  "function declareWinner(uint256 roundId, uint8 laneId) external",
  "function distributePrizes(uint256 roundId) external",
  "function claimPrize(uint256 roundId) external returns (uint256 amount)",
  "function sweepUnclaimed(uint256 roundId) external",
  "function abortRace(uint256 roundId) external",
  "function claimRefund(uint256 roundId) external returns (uint256 amount)",
  "function getRoundClaimInfo(uint256 roundId) external view returns (uint48 settledAt, uint48 claimWindowSnapshot, bool claimsSwept, bool prizesDistributed)",
  "function getRoundWinner(uint256 roundId) external view returns (uint8 winnerLaneId)",
  "function getRoundState(uint256 roundId) external view returns (uint8 state)",
  "function getLane(uint256 roundId, uint8 laneId) external view returns (uint64[] chainPath, uint8 hopsCompleted, uint8 requiredHops, uint256 totalLatency, uint256 finishTime, bool finished)",
  "function currentRoundId() external view returns (uint256)",
  "event RoundCreated(uint256 indexed roundId, uint8 laneCount)",
  "event BetPlaced(uint256 indexed roundId, uint8 indexed laneId, address indexed bettor, uint256 amount)",
  "event RaceStarted(uint256 indexed roundId)",
  "event HopCompleted(uint256 indexed roundId, uint8 indexed laneId, uint64 chainSelector, uint256 latency, uint8 hopIndex)",
  "event LaneFinished(uint256 indexed roundId, uint8 indexed laneId, uint256 finishTime)",
  "event WinnerDeclared(uint256 indexed roundId, uint8 indexed laneId, uint256 finishTime)",
  "event PrizesDistributed(uint256 indexed roundId, uint8 winnerLaneId, uint256 winnerPayout)",
  "event PrizeClaimed(uint256 indexed roundId, address indexed bettor, uint256 amount)",
]);

export const LAST_FINALIZED_BLOCK = 0n;

/** RoundState enum values from LaneController.sol */
export const RoundState = {
  Betting: 0,
  Racing: 1,
  Finished: 2,
  Settled: 3,
  Aborted: 4,
} as const;
