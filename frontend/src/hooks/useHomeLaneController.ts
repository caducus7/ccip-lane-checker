"use client";

import { useReadContract } from "wagmi";
import { sepolia } from "viem/chains";
import {
  getHomeLaneController,
  isDeployed,
  laneControllerAbi,
} from "@/lib/contracts";

export const HOME_CHAIN_ID = sepolia.id;

function homeController() {
  return getHomeLaneController();
}

export function useHomeRoundCounter() {
  const controller = homeController();

  return useReadContract({
    chainId: HOME_CHAIN_ID,
    address: controller,
    abi: laneControllerAbi,
    functionName: "currentRoundId",
    query: {
      enabled: isDeployed(controller),
      refetchInterval: 10_000,
    },
  });
}

export function useHomeRoundState(roundId: bigint | undefined) {
  const controller = homeController();

  return useReadContract({
    chainId: HOME_CHAIN_ID,
    address: controller,
    abi: laneControllerAbi,
    functionName: "getRoundState",
    args: roundId !== undefined ? [roundId] : undefined,
    query: {
      enabled: roundId !== undefined && isDeployed(controller),
      refetchInterval: 5_000,
    },
  });
}

export function useHomeRoundWinner(roundId: bigint | undefined) {
  const controller = homeController();

  return useReadContract({
    chainId: HOME_CHAIN_ID,
    address: controller,
    abi: laneControllerAbi,
    functionName: "getRoundWinner",
    args: roundId !== undefined ? [roundId] : undefined,
    query: {
      enabled: roundId !== undefined && isDeployed(controller),
      refetchInterval: 5_000,
    },
  });
}

export function useHomeLanePool(roundId: bigint | undefined, laneId: number) {
  const controller = homeController();

  return useReadContract({
    chainId: HOME_CHAIN_ID,
    address: controller,
    abi: laneControllerAbi,
    functionName: "getLanePool",
    args: roundId !== undefined ? [roundId, laneId] : undefined,
    query: {
      enabled: roundId !== undefined && isDeployed(controller),
      refetchInterval: 3_000,
    },
  });
}

export function useHomeTotalPrizePool(roundId: bigint | undefined) {
  const controller = homeController();

  return useReadContract({
    chainId: HOME_CHAIN_ID,
    address: controller,
    abi: laneControllerAbi,
    functionName: "getTotalPrizePool",
    args: roundId !== undefined ? [roundId] : undefined,
    query: {
      enabled: roundId !== undefined && isDeployed(controller),
      refetchInterval: 5_000,
    },
  });
}

export function useHomeLane(roundId: bigint | undefined, laneId: number) {
  const controller = homeController();

  return useReadContract({
    chainId: HOME_CHAIN_ID,
    address: controller,
    abi: laneControllerAbi,
    functionName: "getLane",
    args: roundId !== undefined ? [roundId, laneId] : undefined,
    query: {
      enabled: roundId !== undefined && isDeployed(controller),
      refetchInterval: 3_000,
    },
  });
}

export function useControllerOwner() {
  const controller = homeController();

  return useReadContract({
    chainId: HOME_CHAIN_ID,
    address: controller,
    abi: laneControllerAbi,
    functionName: "owner",
    query: {
      enabled: isDeployed(controller),
    },
  });
}
