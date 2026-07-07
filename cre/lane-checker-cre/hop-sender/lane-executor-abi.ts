import { parseAbi } from "viem";

/** LaneExecutor — hop orchestration via CRE writeReport to onReport or direct hopSender call. */
export const laneExecutorAbi = parseAbi([
  "function sendHop(uint256 roundId, uint8 laneId, uint64 destChainSelector) external returns (bytes32 messageId)",
  "function setRemoteExecutor(uint64 chainSelector, address executor) external",
  "function setHopSender(address sender, bool allowed) external",
  "function setCreForwarder(address forwarder) external",
  "function onReport(bytes metadata, bytes report) external",
  "event HopSent(bytes32 indexed messageId, uint256 indexed roundId, uint8 indexed laneId, uint64 destChainSelector)",
  "event HopReceived(uint256 indexed roundId, uint8 indexed laneId, uint64 sourceChainSelector, uint256 latency)",
]);
