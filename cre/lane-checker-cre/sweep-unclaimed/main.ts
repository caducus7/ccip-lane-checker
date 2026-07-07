import {
  cre,
  handler,
  Runner,
  type CronPayload,
  type Runtime,
  bytesToHex,
  encodeCallMsg,
  LAST_FINALIZED_BLOCK_NUMBER,
} from "@chainlink/cre-sdk";
import { decodeFunctionResult, encodeFunctionData, zeroAddress } from "viem";
import { laneControllerAbi, RoundState } from "./lane-controller-abi";
import {
  buildSweepResult,
  isEligibleForSweep,
  roundIdsToScan,
} from "./logic";
import {
  controllerAddress,
  createEvmClient,
  writeLaneController,
} from "./evm-write";

export type Config = {
  schedule: string;
  laneControllerAddress: string;
  chainSelectorName: string;
  gasLimit?: string;
  /** Seconds after winner finish time before sweeping unclaimed shares. */
  claimWindowSeconds: number;
  /** Max settled rounds to scan per CRON tick. */
  lookbackMaxRounds: number;
};

const readCurrentRoundId = (runtime: Runtime<Config>): bigint => {
  const evmClient = createEvmClient(runtime.config);
  const callData = encodeFunctionData({
    abi: laneControllerAbi,
    functionName: "currentRoundId",
  });

  const result = evmClient
    .callContract(runtime, {
      call: encodeCallMsg({
        from: zeroAddress,
        to: controllerAddress(runtime.config),
        data: callData,
      }),
      blockNumber: LAST_FINALIZED_BLOCK_NUMBER,
    })
    .result();

  return decodeFunctionResult({
    abi: laneControllerAbi,
    functionName: "currentRoundId",
    data: bytesToHex(result.data),
  }) as bigint;
};

const readRoundState = (runtime: Runtime<Config>, roundId: bigint): number => {
  const evmClient = createEvmClient(runtime.config);
  const callData = encodeFunctionData({
    abi: laneControllerAbi,
    functionName: "getRoundState",
    args: [roundId],
  });

  const result = evmClient
    .callContract(runtime, {
      call: encodeCallMsg({
        from: zeroAddress,
        to: controllerAddress(runtime.config),
        data: callData,
      }),
      blockNumber: LAST_FINALIZED_BLOCK_NUMBER,
    })
    .result();

  return Number(
    decodeFunctionResult({
      abi: laneControllerAbi,
      functionName: "getRoundState",
      data: bytesToHex(result.data),
    }),
  );
};

const readWinnerLaneId = (
  runtime: Runtime<Config>,
  roundId: bigint,
): number => {
  const evmClient = createEvmClient(runtime.config);
  const callData = encodeFunctionData({
    abi: laneControllerAbi,
    functionName: "getRoundWinner",
    args: [roundId],
  });

  const result = evmClient
    .callContract(runtime, {
      call: encodeCallMsg({
        from: zeroAddress,
        to: controllerAddress(runtime.config),
        data: callData,
      }),
      blockNumber: LAST_FINALIZED_BLOCK_NUMBER,
    })
    .result();

  return Number(
    decodeFunctionResult({
      abi: laneControllerAbi,
      functionName: "getRoundWinner",
      data: bytesToHex(result.data),
    }),
  );
};

const readWinnerFinishTime = (
  runtime: Runtime<Config>,
  roundId: bigint,
  winnerLaneId: number,
): bigint => {
  const evmClient = createEvmClient(runtime.config);
  const callData = encodeFunctionData({
    abi: laneControllerAbi,
    functionName: "getLane",
    args: [roundId, winnerLaneId],
  });

  const result = evmClient
    .callContract(runtime, {
      call: encodeCallMsg({
        from: zeroAddress,
        to: controllerAddress(runtime.config),
        data: callData,
      }),
      blockNumber: LAST_FINALIZED_BLOCK_NUMBER,
    })
    .result();

  const decoded = decodeFunctionResult({
    abi: laneControllerAbi,
    functionName: "getLane",
    data: bytesToHex(result.data),
  }) as readonly [readonly bigint[], number, number, bigint, bigint, boolean];

  return decoded[4];
};

const onCronTrigger = (
  runtime: Runtime<Config>,
  payload: CronPayload,
): string => {
  const scheduledAt =
    payload.scheduledExecutionTime?.seconds?.toString() ??
    runtime.now().toISOString();

  runtime.log(`sweep-unclaimed CRON fired at ${scheduledAt}`);

  const currentRoundId = readCurrentRoundId(runtime);
  const roundIds = roundIdsToScan(
    currentRoundId,
    runtime.config.lookbackMaxRounds,
  );

  const nowSeconds = BigInt(
    Math.floor(new Date(runtime.now()).getTime() / 1000),
  );
  const evmClient = createEvmClient(runtime.config);
  const swept: Array<{ roundId: string; tx: string }> = [];
  const skipped: Array<{ roundId: string; reason: string }> = [];

  for (const roundId of roundIds) {
    const roundState = readRoundState(runtime, roundId);
    const winnerLaneId = readWinnerLaneId(runtime, roundId);
    const winnerFinishTime = readWinnerFinishTime(
      runtime,
      roundId,
      winnerLaneId,
    );

    if (
      !isEligibleForSweep({
        roundState,
        winnerLaneId,
        winnerFinishTime,
        nowSeconds,
        claimWindowSeconds: runtime.config.claimWindowSeconds,
      })
    ) {
      skipped.push({
        roundId: roundId.toString(),
        reason:
          roundState !== RoundState.Settled
            ? "not-settled-or-in-claim-window"
            : "not-eligible",
      });
      continue;
    }

    const tx = writeLaneController(
      runtime,
      evmClient,
      laneControllerAbi,
      "sweepUnclaimed",
      [roundId],
    );
    swept.push({ roundId: roundId.toString(), tx });
  }

  const result = buildSweepResult({
    scheduledAt,
    claimWindowSeconds: runtime.config.claimWindowSeconds,
    scanned: roundIds.length,
    swept,
    skipped,
  });

  runtime.log(result);
  return result;
};

export const initWorkflow = (config: Config) => {
  const cron = new cre.capabilities.CronCapability();
  return [
    handler(cron.trigger({ schedule: config.schedule }), onCronTrigger),
  ];
};

export async function main() {
  const runner = await Runner.newRunner<Config>();
  await runner.run(initWorkflow);
}
