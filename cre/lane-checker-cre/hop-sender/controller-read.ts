import type { Runtime } from "@chainlink/cre-sdk";
import { EVMClient } from "@chainlink/cre-sdk";
import { type Address } from "viem";

type ControllerReadConfig = {
  laneControllerAddress: string;
  controllerChainSelectorName: string;
};

const resolveChainSelector = (config: ControllerReadConfig): bigint => {
  const selector =
    EVMClient.SUPPORTED_CHAIN_SELECTORS[
      config.controllerChainSelectorName as keyof typeof EVMClient.SUPPORTED_CHAIN_SELECTORS
    ];
  if (selector === undefined) {
    throw new Error(
      `Unsupported chain selector name: ${config.controllerChainSelectorName}`,
    );
  }
  return selector;
};

export function createEvmClient(config: ControllerReadConfig): EVMClient {
  return new EVMClient(resolveChainSelector(config));
}

export function controllerAddress(config: ControllerReadConfig): Address {
  return config.laneControllerAddress as Address;
}

export type { Runtime };
