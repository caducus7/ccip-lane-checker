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
