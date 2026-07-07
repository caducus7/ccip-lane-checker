export type LanePath = string[];

export function toSelectorBigints(paths: LanePath[]): bigint[][] {
  return paths.map((lane) => lane.map((selector) => BigInt(selector)));
}

export function computeNextRoundId(currentRoundId: bigint): bigint {
  return currentRoundId + 1n;
}

export function buildRoundSchedulerResult(input: {
  scheduledAt: string;
  createRoundTx: string;
  startRaceTx: string;
  roundId: bigint;
  laneCount: number;
}): string {
  return JSON.stringify({
    action: "round-scheduled",
    scheduledAt: input.scheduledAt,
    createRoundTx: input.createRoundTx,
    startRaceTx: input.startRaceTx,
    roundId: input.roundId.toString(),
    laneCount: input.laneCount,
  });
}
