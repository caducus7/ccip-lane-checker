export function buildSettlementResult(input: {
  roundId: bigint;
  winnerLaneId: number;
  finishTime: bigint;
  distributeTx: string;
  txHash: string;
}): string {
  return JSON.stringify({
    event: "WinnerDeclared",
    action: "distributePrizes",
    roundId: input.roundId.toString(),
    winnerLaneId: input.winnerLaneId,
    finishTime: input.finishTime.toString(),
    distributePrizesTx: input.distributeTx,
    txHash: input.txHash,
  });
}

export function buildSettlementRetryResult(input: {
  scheduledAt: string;
  attempted: Array<{ roundId: string; tx: string | null; reason?: string }>;
}): string {
  return JSON.stringify({
    action: "settlement-retry",
    scheduledAt: input.scheduledAt,
    attempted: input.attempted,
  });
}

/** Finished rounds are settlement candidates (winner declared; runner-up may still be pending). */
export function shouldRetryDistribute(roundState: number, finishedState: number): boolean {
  return roundState === finishedState;
}

/**
 * Abort only when on-chain idle timeout has elapsed (`isRaceAbortable`).
 * Never privileged-abort live Betting/Racing from the settlement retry cron.
 */
export function shouldAttemptAbort(
  roundState: number,
  isAbortable: boolean,
): boolean {
  return (roundState === 0 || roundState === 1) && isAbortable;
}
