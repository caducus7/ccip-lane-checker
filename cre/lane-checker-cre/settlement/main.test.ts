import { describe, expect, test } from "bun:test";
import { RoundState } from "./lane-controller-abi";
import {
  buildSettlementResult,
  buildSettlementRetryResult,
  shouldAttemptAbort,
  shouldRetryDistribute,
} from "./logic";

describe("buildSettlementResult", () => {
  test("maps WinnerDeclared to distributePrizes action", () => {
    const json = buildSettlementResult({
      roundId: 12n,
      winnerLaneId: 1,
      finishTime: 1_700_000_000n,
      distributeTx: "0xdistribute",
      txHash: "0xevent",
    });

    const parsed = JSON.parse(json);
    expect(parsed.action).toBe("distributePrizes");
    expect(parsed.roundId).toBe("12");
    expect(parsed.winnerLaneId).toBe(1);
    expect(parsed.distributePrizesTx).toBe("0xdistribute");
  });
});

describe("shouldRetryDistribute", () => {
  test("retries Finished rounds only", () => {
    expect(shouldRetryDistribute(RoundState.Finished, RoundState.Finished)).toBe(
      true,
    );
    expect(shouldRetryDistribute(RoundState.Settled, RoundState.Finished)).toBe(
      false,
    );
  });
});

describe("shouldAttemptAbort", () => {
  test("requires on-chain idle timeout (isRaceAbortable)", () => {
    expect(shouldAttemptAbort(RoundState.Betting, true)).toBe(true);
    expect(shouldAttemptAbort(RoundState.Racing, true)).toBe(true);
    expect(shouldAttemptAbort(RoundState.Betting, false)).toBe(false);
    expect(shouldAttemptAbort(RoundState.Racing, false)).toBe(false);
    expect(shouldAttemptAbort(RoundState.Finished, true)).toBe(false);
  });
});

describe("buildSettlementRetryResult", () => {
  test("serializes retry attempts", () => {
    const parsed = JSON.parse(
      buildSettlementRetryResult({
        scheduledAt: "1",
        attempted: [{ roundId: "2", tx: null, reason: "RunnerUpPending" }],
      }),
    );
    expect(parsed.action).toBe("settlement-retry");
    expect(parsed.attempted).toHaveLength(1);
  });
});
