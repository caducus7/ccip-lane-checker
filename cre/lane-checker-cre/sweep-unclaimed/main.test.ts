import { describe, expect, test } from "bun:test";
import { RoundState } from "./lane-controller-abi";
import {
  buildSweepResult,
  isEligibleForSweep,
  NO_LANE,
  roundIdsToScan,
} from "./logic";

describe("roundIdsToScan", () => {
  test("returns empty when no rounds exist", () => {
    expect(roundIdsToScan(0n, 10)).toEqual([]);
  });

  test("scans from 1 through current when lookback exceeds history", () => {
    expect(roundIdsToScan(3n, 10)).toEqual([1n, 2n, 3n]);
  });

  test("limits scan window to lookbackMaxRounds", () => {
    expect(roundIdsToScan(10n, 3)).toEqual([8n, 9n, 10n]);
  });
});

describe("isEligibleForSweep", () => {
  const base = {
    roundState: RoundState.Settled,
    winnerLaneId: 0,
    winnerFinishTime: 1_000n,
    claimWindowSeconds: 3600,
  };

  test("accepts settled rounds after claim window", () => {
    expect(
      isEligibleForSweep({
        ...base,
        nowSeconds: 5_000n,
      }),
    ).toBe(true);
  });

  test("rejects rounds still inside claim window", () => {
    expect(
      isEligibleForSweep({
        ...base,
        nowSeconds: 2_000n,
      }),
    ).toBe(false);
  });

  test("rejects non-settled rounds", () => {
    expect(
      isEligibleForSweep({
        ...base,
        roundState: RoundState.Finished,
        nowSeconds: 9_000n,
      }),
    ).toBe(false);
  });

  test("rejects unset winner lane", () => {
    expect(
      isEligibleForSweep({
        ...base,
        winnerLaneId: NO_LANE,
        nowSeconds: 9_000n,
      }),
    ).toBe(false);
  });
});

describe("buildSweepResult", () => {
  test("serializes sweep summary", () => {
    const json = buildSweepResult({
      scheduledAt: "1783432800",
      claimWindowSeconds: 86400,
      scanned: 2,
      swept: [{ roundId: "1", tx: "0xabc" }],
      skipped: [{ roundId: "2", reason: "not-eligible" }],
    });

    const parsed = JSON.parse(json);
    expect(parsed.action).toBe("sweep-unclaimed");
    expect(parsed.swept).toHaveLength(1);
    expect(parsed.skipped).toHaveLength(1);
  });
});
