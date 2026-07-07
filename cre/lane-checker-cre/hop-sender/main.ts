import {
  cre,
  handler,
  Runner,
  type CronPayload,
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
import { laneControllerAbi, RoundState } from "./lane-controller-abi";
import { laneExecutorAbi } from "./lane-executor-abi";
import {
  controllerAddress,
  createEvmClient,
} from "./controller-read";
import {
  createExecutorEvmClient,
  writeLaneExecutor,
} from "./evm-write";
import {
  shouldCronSendInitial,
  shouldProcessHopReceived,
  shouldSendHop,
} from "./logic";

export type Config = {
  schedule: string;
  laneControllerAddress: string;
  controllerChainSelectorName: string;
  laneExecutorAddress: string;
  executorChainSelectorName: string;
  laneCount: number;
  /** When true, CRON sends only initial hops (hopsCompleted === 0). */
  isOriginChain?: boolean;
  gasLimit?: string;
};

const HOP_RECEIVED_SIG = keccak256(
  toBytes("HopReceived(uint256,uint8,uint64,uint256)"),
) as Hex;

type LaneSnapshot = {
  chainPath: readonly bigint[];
  hopsCompleted: number;
  requiredHops: number;
  finished: boolean;
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

const readLane = (
  runtime: Runtime<Config>,
  roundId: bigint,
  laneId: number,
): LaneSnapshot => {
  const evmClient = createEvmClient(runtime.config);
  const callData = encodeFunctionData({
    abi: laneControllerAbi,
    functionName: "getLane",
    args: [roundId, laneId],
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

  return {
    chainPath: decoded[0],
    hopsCompleted: Number(decoded[1]),
    requiredHops: Number(decoded[2]),
    finished: decoded[5],
  };
};

const maybeSendNextHop = (
  runtime: Runtime<Config>,
  roundId: bigint,
  laneId: number,
  initialOnly: boolean,
): string | null => {
  const lane = readLane(runtime, roundId, laneId);
  if (!shouldSendHop(lane, initialOnly)) {
    return null;
  }

  const destSelector = lane.chainPath[lane.hopsCompleted];
  if (destSelector === undefined) {
    runtime.log(`lane ${laneId}: missing chainPath[${lane.hopsCompleted}]`);
    return null;
  }

  const executorClient = createExecutorEvmClient(runtime.config);
  return writeLaneExecutor(
    runtime,
    executorClient,
    laneExecutorAbi,
    "sendHop",
    [roundId, laneId, destSelector],
  );
};

const processActiveLanes = (
  runtime: Runtime<Config>,
  roundId: bigint,
  initialOnly: boolean,
): Array<{ laneId: number; tx: string }> => {
  const sends: Array<{ laneId: number; tx: string }> = [];

  for (let laneId = 0; laneId < runtime.config.laneCount; laneId++) {
    const tx = maybeSendNextHop(runtime, roundId, laneId, initialOnly);
    if (tx) {
      sends.push({ laneId, tx });
    }
  }

  return sends;
};

const onCronTrigger = (
  runtime: Runtime<Config>,
  payload: CronPayload,
): string => {
  const scheduledAt =
    payload.scheduledExecutionTime?.seconds?.toString() ??
    runtime.now().toISOString();

  runtime.log(`hop-sender CRON fired at ${scheduledAt}`);

  const roundId = readCurrentRoundId(runtime);
  const state = readRoundState(runtime, roundId);
  const gate = shouldCronSendInitial({
    isOriginChain: runtime.config.isOriginChain ?? false,
    roundId,
    roundState: state,
  });

  if (!gate.proceed) {
    const skipped =
      gate.reason === "not-origin-chain"
        ? { action: "cron-skipped", reason: gate.reason }
        : {
            action: "idle",
            reason: gate.reason,
            ...(roundId > 0n
              ? { roundId: roundId.toString(), state }
              : {}),
          };
    runtime.log(JSON.stringify(skipped));
    return JSON.stringify(skipped);
  }

  const sends = processActiveLanes(runtime, roundId, true);
  const result = {
    action: "cron-initial-hops",
    scheduledAt,
    roundId: roundId.toString(),
    sends,
  };

  runtime.log(JSON.stringify(result));
  return JSON.stringify(result);
};

const decodeHopReceived = (log: EVMLog) => {
  const topics = log.topics.map((topic) => bytesToHex(topic)) as [
    Hex,
    ...Hex[],
  ];

  return decodeEventLog({
    abi: laneExecutorAbi,
    eventName: "HopReceived",
    data: bytesToHex(log.data),
    topics,
  });
};

const onHopReceived = (runtime: Runtime<Config>, log: EVMLog): string => {
  const decoded = decodeHopReceived(log);
  const { roundId, laneId } = decoded.args;

  const state = readRoundState(runtime, roundId);
  if (!shouldProcessHopReceived(state)) {
    const skipped = {
      event: "HopReceived",
      action: "skipped",
      reason: "round-not-active",
      roundId: roundId.toString(),
      state,
    };
    return JSON.stringify(skipped);
  }

  const tx = maybeSendNextHop(runtime, roundId, Number(laneId), false);
  const result = {
    event: "HopReceived",
    action: tx ? "sendHop" : "no-op",
    roundId: roundId.toString(),
    laneId: Number(laneId),
    sendHopTx: tx,
    txHash: bytesToHex(log.txHash),
  };

  runtime.log(JSON.stringify(result));
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
  const cron = new cre.capabilities.CronCapability();
  const executorClient = new cre.capabilities.EVMClient(
    chainSelector(config.executorChainSelectorName),
  );

  return [
    handler(cron.trigger({ schedule: config.schedule }), onCronTrigger),
    handler(
      executorClient.logTrigger(
        logTriggerConfig({
          addresses: [config.laneExecutorAddress as Hex],
          topics: [[HOP_RECEIVED_SIG]],
        }),
      ),
      onHopReceived,
    ),
  ];
};

export async function main() {
  const runner = await Runner.newRunner<Config>();
  await runner.run(initWorkflow);
}
