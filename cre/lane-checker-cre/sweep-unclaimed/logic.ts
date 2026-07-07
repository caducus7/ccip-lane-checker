import { RoundState } from "./lane-controller-abi";

export const NO_LANE = 255;

export type SweepCandidate = {
  roundId: bigint;
  winnerFinishTime: bigint;
};

export function roundIdsToScan(
  currentRoundId: bigint,
  lookbackMaxRounds: number,
): bigint[] {
  if (currentRoundId === 0n || lookbackMaxRounds <= 0) {
    return [];
  }

  const start =
    currentRoundId > BigInt(lookbackMaxRounds)
      ? currentRoundId - BigInt(lookbackMaxRounds) + 1n
      : 1n;

  const ids: bigint[] = [];
  for (let id = start; id <= currentRoundId; id++) {
    ids.push(id);
  }
  return ids;
}

export function isEligibleForSweep(input: {
  roundState: number;
  winnerLaneId: number;
  winnerFinishTime: bigint;
  nowSeconds: bigint;
  claimWindowSeconds: number;
}): boolean {
  if (input.roundState !== RoundState.Settled) {
    return false;
  }
  if (input.winnerLaneId === NO_LANE) {
    return false;
  }
  if (input.winnerFinishTime === 0n) {
    return false;
  }

  const claimDeadline =
    input.winnerFinishTime + BigInt(input.claimWindowSeconds);
  return input.nowSeconds >= claimDeadline;
}

export function buildSweepResult(input: {
  scheduledAt: string;
  claimWindowSeconds: number;
  scanned: number;
  swept: Array<{ roundId: string; tx: string }>;
  skipped: Array<{ roundId: string; reason: string }>;
}): string {
  return JSON.stringify({
    action: "sweep-unclaimed",
    scheduledAt: input.scheduledAt,
    claimWindowSeconds: input.claimWindowSeconds,
    scanned: input.scanned,
    swept: input.swept,
    skipped: input.skipped,
  });
}
