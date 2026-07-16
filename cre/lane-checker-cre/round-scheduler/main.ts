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
import { laneControllerAbi } from "./lane-controller-abi";
import {
  controllerAddress,
  createEvmClient,
  writeLaneController,
} from "./evm-write";
import {
  buildRoundSchedulerResult,
  computeNextRoundId,
  planRoundSchedulerTick,
  toSelectorBigints,
  type LanePath,
} from "./logic";

export type { LanePath };

export type Config = {
  schedule: string;
  laneControllerAddress: string;
  chainSelectorName: string;
  gasLimit?: string;
  lanePaths: LanePath[];
  /**
   * Seconds bettors get after createRound before startRace.
   * When 0, create+start may run in the same tick (tests only).
   * When >0, each cron tick either creates OR starts — never both.
   */
  bettingWindowSeconds?: number;
};

const readCurrentRoundId = (runtime: Runtime<Config>): bigint => {
  const evmClient = createEvmClient(runtime.config);
  const currentRoundCall = encodeFunctionData({
    abi: laneControllerAbi,
    functionName: "currentRoundId",
  });

  const roundResult = evmClient
    .callContract(runtime, {
      call: encodeCallMsg({
        from: zeroAddress,
        to: controllerAddress(runtime.config),
        data: currentRoundCall,
      }),
      blockNumber: LAST_FINALIZED_BLOCK_NUMBER,
    })
    .result();

  return decodeFunctionResult({
    abi: laneControllerAbi,
    functionName: "currentRoundId",
    data: bytesToHex(roundResult.data),
  }) as bigint;
};

const readRoundState = (
  runtime: Runtime<Config>,
  roundId: bigint,
): number | null => {
  if (roundId === 0n) return null;
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

const onCronTrigger = (
  runtime: Runtime<Config>,
  payload: CronPayload,
): string => {
  const evmClient = createEvmClient(runtime.config);
  const lanePaths = toSelectorBigints(runtime.config.lanePaths);
  const scheduledAt =
    payload.scheduledExecutionTime?.seconds?.toString() ??
    runtime.now().toISOString();
  const bettingWindowSeconds = runtime.config.bettingWindowSeconds ?? 60;

  runtime.log(`round-scheduler fired at ${scheduledAt}`);

  const previousRoundId = readCurrentRoundId(runtime);
  const latestState = readRoundState(runtime, previousRoundId);

  const plan = planRoundSchedulerTick({
    currentRoundId: previousRoundId,
    latestRoundState: latestState,
    bettingWindowSeconds,
  });

  if (plan.action === "skip") {
    const result = buildRoundSchedulerResult({
      scheduledAt,
      createRoundTx: null,
      startRaceTx: null,
      roundId: previousRoundId,
      laneCount: lanePaths.length,
      action: `skip:${plan.reason}`,
    });
    runtime.log(result);
    return result;
  }

  if (plan.action === "start-only") {
    const startTx = writeLaneController(
      runtime,
      evmClient,
      laneControllerAbi,
      "startRace",
      [plan.roundId],
    );
    const result = buildRoundSchedulerResult({
      scheduledAt,
      createRoundTx: null,
      startRaceTx: startTx,
      roundId: plan.roundId,
      laneCount: lanePaths.length,
      action: "start-race",
    });
    runtime.log(result);
    return result;
  }

  const createTx = writeLaneController(
    runtime,
    evmClient,
    laneControllerAbi,
    "createRound",
    [lanePaths],
  );
  const roundId = computeNextRoundId(previousRoundId);
  runtime.log(`createRound tx=${createTx}, roundId=${roundId}`);

  let startTx: string | null = null;
  if (plan.action === "create-and-start") {
    startTx = writeLaneController(
      runtime,
      evmClient,
      laneControllerAbi,
      "startRace",
      [roundId],
    );
  }

  const result = buildRoundSchedulerResult({
    scheduledAt,
    createRoundTx: createTx,
    startRaceTx: startTx,
    roundId,
    laneCount: lanePaths.length,
    action: plan.action === "create-and-start" ? "create-and-start" : "create-only",
  });

  runtime.log(`Round scheduled: ${result}`);
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
