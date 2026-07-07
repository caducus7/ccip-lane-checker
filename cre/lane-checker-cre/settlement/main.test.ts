import { describe, expect, test } from "bun:test";
import { buildSettlementResult } from "./logic";

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
