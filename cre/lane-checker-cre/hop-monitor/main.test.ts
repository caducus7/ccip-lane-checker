import { describe, expect, test } from "bun:test";
import {
  buildHopCompletedResult,
  buildLaneFinishedResult,
} from "./logic";

describe("buildHopCompletedResult", () => {
  test("serializes hop telemetry", () => {
    const json = buildHopCompletedResult({
      roundId: 3n,
      laneId: 0,
      chainSelector: 16015286601757825753n,
      latency: 420n,
      hopIndex: 1,
      txHash: "0xhop",
    });

    const parsed = JSON.parse(json);
    expect(parsed.event).toBe("HopCompleted");
    expect(parsed.hopIndex).toBe(1);
    expect(parsed.chainSelector).toBe("16015286601757825753");
  });
});

describe("buildLaneFinishedResult", () => {
  test("marks lane finish as tracked only", () => {
    const json = buildLaneFinishedResult({
      roundId: 3n,
      laneId: 1,
      finishTime: 99n,
      txHash: "0xfinish",
    });

    const parsed = JSON.parse(json);
    expect(parsed.event).toBe("LaneFinished");
    expect(parsed.action).toBe("tracked");
  });
});
