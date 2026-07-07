import {
  cre,
  handler,
  Runner,
  type EVMLog,
  type Runtime,
  bytesToHex,
  logTriggerConfig,
} from "@chainlink/cre-sdk";
import {
  decodeEventLog,
  keccak256,
  toBytes,
  type Hex,
} from "viem";
import { laneControllerAbi } from "./lane-controller-abi";
import {
  buildHopCompletedResult,
  buildLaneFinishedResult,
} from "./logic";

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

  const result = buildHopCompletedResult({
    roundId,
    laneId: Number(laneId),
    chainSelector,
    latency,
    hopIndex: Number(hopIndex),
    txHash: bytesToHex(log.txHash),
  });

  runtime.log(`HopCompleted: ${result}`);
  return result;
};

const onLaneFinished = (runtime: Runtime<Config>, log: EVMLog): string => {
  const decoded = decodeLaneFinished(log);
  const { roundId, laneId, finishTime } = decoded.args;

  // recordHop auto-declares the first finisher and emits WinnerDeclared;
  // settlement workflow handles distributePrizes + sweepUnclaimed.
  const result = buildLaneFinishedResult({
    roundId,
    laneId: Number(laneId),
    finishTime,
    txHash: bytesToHex(log.txHash),
  });

  runtime.log(`LaneFinished: ${result}`);
  return result;
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
