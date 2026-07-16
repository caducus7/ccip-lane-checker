import { describe, expect, test } from "bun:test";
import { RoundState } from "./lane-controller-abi";
import {
  buildRoundSchedulerResult,
  computeNextRoundId,
  planRoundSchedulerTick,
  toSelectorBigints,
} from "./logic";

describe("toSelectorBigints", () => {
  test("converts string selectors to bigints", () => {
    expect(
      toSelectorBigints([
        ["16015286601757825753", "3478487238524512106"],
      ]),
    ).toEqual([[16015286601757825753n, 3478487238524512106n]]);
  });
});

describe("computeNextRoundId", () => {
  test("increments current round id", () => {
    expect(computeNextRoundId(4n)).toBe(5n);
  });
});

describe("planRoundSchedulerTick", () => {
  test("starts an open betting round instead of creating another", () => {
    expect(
      planRoundSchedulerTick({
        currentRoundId: 3n,
        latestRoundState: RoundState.Betting,
        bettingWindowSeconds: 1800,
      }),
    ).toEqual({ action: "start-only", roundId: 3n });
  });

  test("creates without starting when betting window is required", () => {
    expect(
      planRoundSchedulerTick({
        currentRoundId: 0n,
        latestRoundState: null,
        bettingWindowSeconds: 1800,
      }),
    ).toEqual({ action: "create-only" });
  });

  test("allows create-and-start only when window is zero", () => {
    expect(
      planRoundSchedulerTick({
        currentRoundId: 0n,
        latestRoundState: null,
        bettingWindowSeconds: 0,
      }),
    ).toEqual({ action: "create-and-start" });
  });

  test("skips create while Racing or Finished", () => {
    expect(
      planRoundSchedulerTick({
        currentRoundId: 3n,
        latestRoundState: RoundState.Racing,
        bettingWindowSeconds: 1800,
      }),
    ).toEqual({ action: "skip", reason: "active-round-in-progress" });

    expect(
      planRoundSchedulerTick({
        currentRoundId: 3n,
        latestRoundState: RoundState.Finished,
        bettingWindowSeconds: 0,
      }),
    ).toEqual({ action: "skip", reason: "active-round-in-progress" });
  });
});

describe("buildRoundSchedulerResult", () => {
  test("includes scheduled round metadata", () => {
    const json = buildRoundSchedulerResult({
      scheduledAt: "1783432800",
      createRoundTx: "0xcreate",
      startRaceTx: "0xstart",
      roundId: 7n,
      laneCount: 2,
    });

    const parsed = JSON.parse(json);
    expect(parsed.action).toBe("round-scheduled");
    expect(parsed.roundId).toBe("7");
    expect(parsed.laneCount).toBe(2);
  });
});
