import { describe, expect, test } from "bun:test";
import { RoundState } from "./lane-controller-abi";
import {
  shouldCronSendInitial,
  shouldProcessHopReceived,
  shouldSendHop,
} from "./logic";

describe("shouldCronSendInitial", () => {
  test("skips non-origin chains", () => {
    expect(
      shouldCronSendInitial({
        isOriginChain: false,
        roundId: 1n,
        roundState: RoundState.Racing,
      }),
    ).toEqual({ proceed: false, reason: "not-origin-chain" });
  });

  test("requires an active racing round", () => {
    expect(
      shouldCronSendInitial({
        isOriginChain: true,
        roundId: 2n,
        roundState: RoundState.Racing,
      }).proceed,
    ).toBe(true);

    expect(
      shouldCronSendInitial({
        isOriginChain: true,
        roundId: 2n,
        roundState: RoundState.Betting,
      }).reason,
    ).toBe("not-racing");
  });
});

describe("shouldSendHop", () => {
  const lane = {
    hopsCompleted: 0,
    requiredHops: 3,
    finished: false,
  };

  test("allows initial hop when lane has not started", () => {
    expect(shouldSendHop(lane, true)).toBe(true);
  });

  test("blocks continuation hops during initial-only cron", () => {
    expect(
      shouldSendHop({ ...lane, hopsCompleted: 1 }, true),
    ).toBe(false);
  });
});

describe("shouldProcessHopReceived", () => {
  test("accepts racing and finished rounds", () => {
    expect(shouldProcessHopReceived(RoundState.Racing)).toBe(true);
    expect(shouldProcessHopReceived(RoundState.Finished)).toBe(true);
    expect(shouldProcessHopReceived(RoundState.Settled)).toBe(false);
  });
});
