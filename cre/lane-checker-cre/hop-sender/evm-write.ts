import type { Runtime } from "@chainlink/cre-sdk";
import {
  EVMClient,
  prepareReportRequest,
  bytesToHex,
} from "@chainlink/cre-sdk";
import { encodeFunctionData, type Abi, type Address, type Hex } from "viem";

type ExecutorWriteConfig = {
  laneExecutorAddress: string;
  executorChainSelectorName?: string;
  gasLimit?: string;
};

const resolveChainSelector = (config: ExecutorWriteConfig): bigint => {
  const name = config.executorChainSelectorName;
  if (!name) {
    throw new Error("executorChainSelectorName required");
  }

  const selector =
    EVMClient.SUPPORTED_CHAIN_SELECTORS[
      name as keyof typeof EVMClient.SUPPORTED_CHAIN_SELECTORS
    ];
  if (selector === undefined) {
    throw new Error(`Unsupported chain selector name: ${name}`);
  }
  return selector;
};

export function writeLaneExecutor(
  runtime: Runtime<ExecutorWriteConfig>,
  evmClient: EVMClient,
  abi: Abi,
  functionName: string,
  args: readonly unknown[],
): string {
  const writeData = encodeFunctionData({
    abi,
    functionName,
    args: args as never,
  });

  const report = runtime.report(prepareReportRequest(writeData as Hex)).result();
  const gasLimit = runtime.config.gasLimit ?? "500000";

  const txResult = evmClient
    .writeReport(runtime, {
      receiver: runtime.config.laneExecutorAddress,
      report,
      gasConfig: { gasLimit },
    })
    .result();

  const txHash = txResult.txHash ? bytesToHex(txResult.txHash) : "pending";

  runtime.log(
    `writeReport ${functionName} tx=${txHash} status=${txResult.txStatus}`,
  );

  return txHash;
}

export function createExecutorEvmClient(config: ExecutorWriteConfig): EVMClient {
  return new EVMClient(resolveChainSelector(config));
}

export function executorAddress(config: ExecutorWriteConfig): Address {
  return config.laneExecutorAddress as Address;
}
