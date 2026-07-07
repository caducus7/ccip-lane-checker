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
import { createEvmClient, writeLaneController } from "./evm-write";

export type Config = {
  laneControllerAddress: string;
  chainSelectorName: string;
  gasLimit?: string;
};

const WINNER_DECLARED_SIG = keccak256(
  toBytes("WinnerDeclared(uint256,uint8,uint256)"),
) as Hex;

const onWinnerDeclared = (runtime: Runtime<Config>, log: EVMLog): string => {
  const topics = log.topics.map((topic) => bytesToHex(topic)) as [
    Hex,
    ...Hex[],
  ];

  const decoded = decodeEventLog({
    abi: laneControllerAbi,
    eventName: "WinnerDeclared",
    data: bytesToHex(log.data),
    topics,
  });

  const { roundId, laneId, finishTime } = decoded.args;

  runtime.log(
    `WinnerDeclared round=${roundId} lane=${laneId} finishTime=${finishTime}`,
  );

  const evmClient = createEvmClient(runtime.config);
  const distributeTx = writeLaneController(
    runtime,
    evmClient,
    laneControllerAbi,
    "distributePrizes",
    [roundId],
  );

  const sweepTx = writeLaneController(
    runtime,
    evmClient,
    laneControllerAbi,
    "sweepUnclaimed",
    [roundId],
  );

  const result = {
    event: "WinnerDeclared",
    action: "distributePrizes+sweepUnclaimed",
    roundId: roundId.toString(),
    winnerLaneId: Number(laneId),
    finishTime: finishTime.toString(),
    distributePrizesTx: distributeTx,
    sweepUnclaimedTx: sweepTx,
    txHash: bytesToHex(log.txHash),
  };

  runtime.log(`Prizes distributed: ${JSON.stringify(result)}`);
  return JSON.stringify(result);
};

export const initWorkflow = (config: Config) => {
  const selector =
    cre.capabilities.EVMClient.SUPPORTED_CHAIN_SELECTORS[
      config.chainSelectorName as keyof typeof cre.capabilities.EVMClient.SUPPORTED_CHAIN_SELECTORS
    ];
  if (selector === undefined) {
    throw new Error(`Unsupported chain: ${config.chainSelectorName}`);
  }

  const evmClient = new cre.capabilities.EVMClient(selector);

  return [
    handler(
      evmClient.logTrigger(
        logTriggerConfig({
          addresses: [config.laneControllerAddress as Hex],
          topics: [[WINNER_DECLARED_SIG]],
        }),
      ),
      onWinnerDeclared,
    ),
  ];
};

export async function main() {
  const runner = await Runner.newRunner<Config>();
  await runner.run(initWorkflow);
}
