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
import { createEvmClient, writeLaneController } from "./evm-write";
import {
  buildSettlementResult,
  buildSettlementRetryResult,
  shouldAttemptAbort,
  shouldRetryDistribute,
} from "./logic";

export type Config = {
  laneControllerAddress: string;
  chainSelectorName: string;
  gasLimit?: string;
  /** CRON schedule for settlement retries (RunnerUpPending / missed log). */
  retrySchedule?: string;
  lookbackMaxRounds?: number;
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
  let distributeTx = "";
  try {
    distributeTx = writeLaneController(
      runtime,
      evmClient,
      laneControllerAbi,
      "distributePrizes",
      [roundId],
    );
  } catch (err) {
    runtime.log(
      `distributePrizes deferred (likely RunnerUpPending): ${String(err)}`,
    );
  }

  const result = buildSettlementResult({
    roundId,
    winnerLaneId: Number(laneId),
    finishTime,
    distributeTx: distributeTx || "deferred",
    txHash: bytesToHex(log.txHash),
  });

  runtime.log(`Settlement attempt: ${result}`);
  return result;
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
        to: runtime.config.laneControllerAddress as Hex,
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
        to: runtime.config.laneControllerAddress as Hex,
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

const readIsRaceAbortable = (
  runtime: Runtime<Config>,
  roundId: bigint,
): boolean => {
  const evmClient = createEvmClient(runtime.config);
  const callData = encodeFunctionData({
    abi: laneControllerAbi,
    functionName: "isRaceAbortable",
    args: [roundId],
  });
  const result = evmClient
    .callContract(runtime, {
      call: encodeCallMsg({
        from: zeroAddress,
        to: runtime.config.laneControllerAddress as Hex,
        data: callData,
      }),
      blockNumber: LAST_FINALIZED_BLOCK_NUMBER,
    })
    .result();
  return Boolean(
    decodeFunctionResult({
      abi: laneControllerAbi,
      functionName: "isRaceAbortable",
      data: bytesToHex(result.data),
    }),
  );
};

const onRetryCron = (
  runtime: Runtime<Config>,
  payload: CronPayload,
): string => {
  const scheduledAt =
    payload.scheduledExecutionTime?.seconds?.toString() ??
    runtime.now().toISOString();
  const lookback = runtime.config.lookbackMaxRounds ?? 20;
  const current = readCurrentRoundId(runtime);
  const start =
    current > BigInt(lookback) ? current - BigInt(lookback) + 1n : 1n;
  const evmClient = createEvmClient(runtime.config);
  const attempted: Array<{ roundId: string; tx: string | null; reason?: string }> =
    [];

  for (let id = start; id <= current; id++) {
    const state = readRoundState(runtime, id);
    if (shouldRetryDistribute(state, RoundState.Finished)) {
      try {
        const tx = writeLaneController(
          runtime,
          evmClient,
          laneControllerAbi,
          "distributePrizes",
          [id],
        );
        attempted.push({ roundId: id.toString(), tx });
      } catch (err) {
        attempted.push({
          roundId: id.toString(),
          tx: null,
          reason: String(err),
        });
      }
      continue;
    }

    const abortable = readIsRaceAbortable(runtime, id);
    if (shouldAttemptAbort(state, abortable)) {
      try {
        const tx = writeLaneController(
          runtime,
          evmClient,
          laneControllerAbi,
          "abortRace",
          [id],
        );
        attempted.push({ roundId: id.toString(), tx, reason: "abort-attempt" });
      } catch (err) {
        attempted.push({
          roundId: id.toString(),
          tx: null,
          reason: `abort:${String(err)}`,
        });
      }
      continue;
    }

    attempted.push({
      roundId: id.toString(),
      tx: null,
      reason: abortable ? "not-actionable" : "not-abortable-yet",
    });
  }

  const result = buildSettlementRetryResult({ scheduledAt, attempted });
  runtime.log(result);
  return result;
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
  const handlers = [
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

  if (config.retrySchedule) {
    const cron = new cre.capabilities.CronCapability();
    handlers.push(
      handler(cron.trigger({ schedule: config.retrySchedule }), onRetryCron),
    );
  }

  return handlers;
};

export async function main() {
  const runner = await Runner.newRunner<Config>();
  await runner.run(initWorkflow);
}
