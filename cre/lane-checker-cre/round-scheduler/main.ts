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

  runtime.log(`round-scheduler fired at ${scheduledAt}`);

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

  const previousRoundId = decodeFunctionResult({
    abi: laneControllerAbi,
    functionName: "currentRoundId",
    data: bytesToHex(roundResult.data),
  }) as bigint;

  // createRound does ++currentRoundId; read before write to avoid stale post-write view.
  const roundId = computeNextRoundId(previousRoundId);

  const createTx = writeLaneController(
    runtime,
    evmClient,
    laneControllerAbi,
    "createRound",
    [lanePaths],
  );

  runtime.log(`createRound tx=${createTx}, roundId=${roundId}`);

  const startTx = writeLaneController(
    runtime,
    evmClient,
    laneControllerAbi,
    "startRace",
    [roundId],
  );

  const result = buildRoundSchedulerResult({
    scheduledAt,
    createRoundTx: createTx,
    startRaceTx: startTx,
    roundId,
    laneCount: lanePaths.length,
  });

  runtime.log(`Round started: ${result}`);
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
