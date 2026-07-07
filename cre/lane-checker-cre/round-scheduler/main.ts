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

export type LanePath = string[];

export type Config = {
  schedule: string;
  laneControllerAddress: string;
  chainSelectorName: string;
  gasLimit?: string;
  lanePaths: LanePath[];
};

const toSelectorBigints = (paths: LanePath[]): bigint[][] =>
  paths.map((lane) => lane.map((selector) => BigInt(selector)));

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

  const createTx = writeLaneController(
    runtime,
    evmClient,
    laneControllerAbi,
    "createRound",
    [lanePaths],
  );

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

  const roundId = decodeFunctionResult({
    abi: laneControllerAbi,
    functionName: "currentRoundId",
    data: bytesToHex(roundResult.data),
  }) as bigint;

  runtime.log(`createRound tx=${createTx}, currentRoundId=${roundId}`);

  const startTx = writeLaneController(
    runtime,
    evmClient,
    laneControllerAbi,
    "startRace",
    [roundId],
  );

  const result = {
    action: "round-scheduled",
    scheduledAt,
    createRoundTx: createTx,
    startRaceTx: startTx,
    roundId: roundId.toString(),
    laneCount: lanePaths.length,
  };

  runtime.log(`Round started: ${JSON.stringify(result)}`);
  return JSON.stringify(result);
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
