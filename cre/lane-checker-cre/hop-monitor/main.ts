import {
  cre,
  handler,
  Runner,
  type EVMLog,
  type Runtime,
  bytesToHex,
  encodeCallMsg,
  LAST_FINALIZED_BLOCK_NUMBER,
  logTriggerConfig,
} from "@chainlink/cre-sdk";
import {
  decodeEventLog,
  decodeFunctionResult,
  encodeFunctionData,
  keccak256,
  toBytes,
  zeroAddress,
  type Hex,
} from "viem";
import { laneControllerAbi } from "./lane-controller-abi";
import {
  controllerAddress,
  createEvmClient,
  writeLaneController,
} from "./evm-write";

export type ChainConfig = {
  chainSelectorName: string;
};

export type Config = {
  laneControllerAddress: string;
  controllerChainSelectorName: string;
  gasLimit?: string;
  chains: ChainConfig[];
};

const HOP_COMPLETED_SIG = keccak256(
  toBytes("HopCompleted(uint256,uint8,uint64,uint256,uint8)"),
) as Hex;
const LANE_FINISHED_SIG = keccak256(
  toBytes("LaneFinished(uint256,uint8,uint256)"),
) as Hex;

const getWinnerLane = (runtime: Runtime<Config>, roundId: bigint): number => {
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

  return decodeFunctionResult({
    abi: laneControllerAbi,
    functionName: "getRoundWinner",
    data: bytesToHex(result.data),
  }) as number;
};

const decodeHopCompleted = (log: EVMLog) => {
  const topics = log.topics.map((topic) => bytesToHex(topic)) as [
    Hex,
    ...Hex[],
  ];

  return decodeEventLog({
    abi: laneControllerAbi,
    eventName: "HopCompleted",
    data: bytesToHex(log.data),
    topics,
  });
};

const decodeLaneFinished = (log: EVMLog) => {
  const topics = log.topics.map((topic) => bytesToHex(topic)) as [
    Hex,
    ...Hex[],
  ];

  return decodeEventLog({
    abi: laneControllerAbi,
    eventName: "LaneFinished",
    data: bytesToHex(log.data),
    topics,
  });
};

const onHopCompleted = (runtime: Runtime<Config>, log: EVMLog): string => {
  const decoded = decodeHopCompleted(log);
  const { roundId, laneId, chainSelector, latency, hopIndex } = decoded.args;

  const result = {
    event: "HopCompleted",
    roundId: roundId.toString(),
    laneId: Number(laneId),
    chainSelector: chainSelector.toString(),
    latency: latency.toString(),
    hopIndex: Number(hopIndex),
    txHash: bytesToHex(log.txHash),
  };

  runtime.log(`HopCompleted: ${JSON.stringify(result)}`);
  return JSON.stringify(result);
};

const onLaneFinished = (runtime: Runtime<Config>, log: EVMLog): string => {
  const decoded = decodeLaneFinished(log);
  const { roundId, laneId, finishTime } = decoded.args;

  runtime.log(
    `LaneFinished round=${roundId} lane=${laneId} finishTime=${finishTime}`,
  );

  const existingWinner = getWinnerLane(runtime, roundId);
  const NO_LANE = 255; // type(uint8).max — matches LaneController.NO_LANE

  if (existingWinner !== NO_LANE) {
    const skipped = {
      event: "LaneFinished",
      action: "skipped",
      reason: "winner-already-declared",
      roundId: roundId.toString(),
      existingWinner: existingWinner.toString(),
    };
    runtime.log(JSON.stringify(skipped));
    return JSON.stringify(skipped);
  }

  const evmClient = createEvmClient(runtime.config);
  const declareTx = writeLaneController(
    runtime,
    evmClient,
    laneControllerAbi,
    "declareWinner",
    [roundId, laneId],
  );

  const result = {
    event: "LaneFinished",
    action: "declareWinner",
    roundId: roundId.toString(),
    laneId: Number(laneId),
    finishTime: finishTime.toString(),
    declareWinnerTx: declareTx,
    txHash: bytesToHex(log.txHash),
  };

  runtime.log(`First finisher — winner declared: ${JSON.stringify(result)}`);
  return JSON.stringify(result);
};

const chainSelector = (name: string): bigint => {
  const selector =
    cre.capabilities.EVMClient.SUPPORTED_CHAIN_SELECTORS[
      name as keyof typeof cre.capabilities.EVMClient.SUPPORTED_CHAIN_SELECTORS
    ];
  if (selector === undefined) {
    throw new Error(`Unsupported chain: ${name}`);
  }
  return selector;
};

export const initWorkflow = (config: Config) => {
  const handlers = [];
  const controller = config.laneControllerAddress as Hex;

  for (const chain of config.chains) {
    const evmClient = new cre.capabilities.EVMClient(
      chainSelector(chain.chainSelectorName),
    );

    handlers.push(
      handler(
        evmClient.logTrigger(
          logTriggerConfig({
            addresses: [controller],
            topics: [[HOP_COMPLETED_SIG]],
          }),
        ),
        onHopCompleted,
      ),
      handler(
        evmClient.logTrigger(
          logTriggerConfig({
            addresses: [controller],
            topics: [[LANE_FINISHED_SIG]],
          }),
        ),
        onLaneFinished,
      ),
    );
  }

  return handlers;
};

export async function main() {
  const runner = await Runner.newRunner<Config>();
  await runner.run(initWorkflow);
}
