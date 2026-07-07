export function buildHopCompletedResult(input: {
  roundId: bigint;
  laneId: number;
  chainSelector: bigint;
  latency: bigint;
  hopIndex: number;
  txHash: string;
}): string {
  return JSON.stringify({
    event: "HopCompleted",
    roundId: input.roundId.toString(),
    laneId: input.laneId,
    chainSelector: input.chainSelector.toString(),
    latency: input.latency.toString(),
    hopIndex: input.hopIndex,
    txHash: input.txHash,
  });
}

export function buildLaneFinishedResult(input: {
  roundId: bigint;
  laneId: number;
  finishTime: bigint;
  txHash: string;
}): string {
  return JSON.stringify({
    event: "LaneFinished",
    action: "tracked",
    roundId: input.roundId.toString(),
    laneId: input.laneId,
    finishTime: input.finishTime.toString(),
    txHash: input.txHash,
  });
}
