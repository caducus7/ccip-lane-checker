export type LanePath = string[];

export function toSelectorBigints(paths: LanePath[]): bigint[][] {
  return paths.map((lane) => lane.map((selector) => BigInt(selector)));
}

export function computeNextRoundId(currentRoundId: bigint): bigint {
  return currentRoundId + 1n;
}

export type RoundSchedulerAction =
  | { action: "create-only" }
  | { action: "start-only"; roundId: bigint }
  | { action: "create-and-start" }
  | { action: "skip"; reason: string };

/**
 * Never createRound + startRace in the same tick when bettingWindowSeconds > 0.
 * Cron interval then acts as the betting window between create and start ticks.
 * Skip create while Betting (start instead), Racing, or Finished (await settle).
 */
export function planRoundSchedulerTick(input: {
  currentRoundId: bigint;
  latestRoundState: number | null;
  bettingWindowSeconds: number;
}): RoundSchedulerAction {
  const Betting = 0;
  const Racing = 1;
  const Finished = 2;
  const { currentRoundId, latestRoundState, bettingWindowSeconds } = input;

  if (currentRoundId > 0n && latestRoundState === Betting) {
    return { action: "start-only", roundId: currentRoundId };
  }

  if (
    currentRoundId > 0n &&
    (latestRoundState === Racing || latestRoundState === Finished)
  ) {
    return { action: "skip", reason: "active-round-in-progress" };
  }

  if (bettingWindowSeconds <= 0) {
    return { action: "create-and-start" };
  }

  return { action: "create-only" };
}

export function buildRoundSchedulerResult(input: {
  scheduledAt: string;
  createRoundTx: string | null;
  startRaceTx: string | null;
  roundId: bigint;
  laneCount: number;
  action?: string;
}): string {
  return JSON.stringify({
    action: input.action ?? "round-scheduled",
    scheduledAt: input.scheduledAt,
    createRoundTx: input.createRoundTx,
    startRaceTx: input.startRaceTx,
    roundId: input.roundId.toString(),
    laneCount: input.laneCount,
  });
}
