"use client";

import { useAccount } from "wagmi";
import {
  getDeploymentByChainId,
  hasAnyDeployment,
  isDeployed,
} from "@/lib/contracts";

export function useDeploymentStatus() {
  const { chainId, isConnected } = useAccount();
  const deployment = chainId ? getDeploymentByChainId(chainId) : undefined;

  return {
    isConnected,
    chainId,
    deployment,
    controllerDeployed: isDeployed(deployment?.laneController),
    laneTokenDeployed: isDeployed(deployment?.laneToken),
    anyDeployed: hasAnyDeployment(),
  };
}
