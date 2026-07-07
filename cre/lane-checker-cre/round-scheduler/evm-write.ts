import type { Runtime } from "@chainlink/cre-sdk";
import {
  EVMClient,
  prepareReportRequest,
  bytesToHex,
} from "@chainlink/cre-sdk";
import { encodeFunctionData, type Abi, type Address, type Hex } from "viem";

type WriteConfig = {
  laneControllerAddress: string;
  chainSelectorName?: string;
  controllerChainSelectorName?: string;
  gasLimit?: string;
};

const resolveChainSelector = (config: WriteConfig): bigint => {
  const name =
    config.chainSelectorName ?? config.controllerChainSelectorName;
  if (!name) {
    throw new Error("chainSelectorName or controllerChainSelectorName required");
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

export function writeLaneController(
  runtime: Runtime<WriteConfig>,
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
  const gasLimit = runtime.config.gasLimit ?? "800000";

  const txResult = evmClient
    .writeReport(runtime, {
      receiver: runtime.config.laneControllerAddress,
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

export function createEvmClient(config: WriteConfig): EVMClient {
  return new EVMClient(resolveChainSelector(config));
}

export function controllerAddress(config: WriteConfig): Address {
  return config.laneControllerAddress as Address;
}
