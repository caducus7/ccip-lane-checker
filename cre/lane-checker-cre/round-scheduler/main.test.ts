import { describe, expect, test } from "bun:test";
import {
  buildRoundSchedulerResult,
  computeNextRoundId,
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
