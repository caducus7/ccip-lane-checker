"use client";

import { useAccount } from "wagmi";
import {
  getDeploymentByChainId,
  getHomeLaneController,
  hasAnyDeployment,
  hasLaneTokenDeployment,
  isDeployed,
} from "@/lib/contracts";

/**
 * Deployment readiness for UI banners.
 *
 * Manifest addresses (testnet.json) are the source of truth. Wallet
 * connection / current chain only gate *writes*, never whether contracts
 * are considered deployed.
 */
export function useDeploymentStatus() {
  const { chainId, isConnected } = useAccount();
  const deployment = chainId ? getDeploymentByChainId(chainId) : undefined;
  const homeController = getHomeLaneController();

  return {
    isConnected,
    chainId,
    deployment,
    /** Home-chain LaneController (Sepolia) — use for parimutuel UI. */
    controllerDeployed: isDeployed(homeController),
    /** LaneToken exists on any configured testnet. */
    laneTokenDeployed: hasLaneTokenDeployment(),
    /** LaneToken on the wallet's current chain (solo writes). */
    laneTokenOnCurrentChain: isDeployed(deployment?.laneToken),
    /** True if any supported testnet has LaneController or LaneToken. */
    anyDeployed: hasAnyDeployment(),
  };
}
