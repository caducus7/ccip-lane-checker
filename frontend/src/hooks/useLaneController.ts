"use client";

import {
  useAccount,
  useReadContract,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import { parseUnits } from "viem";
import {
  erc20Abi,
  getDeploymentByChainId,
  getLaneControllerAddress,
  isDeployed,
  laneControllerAbi,
} from "@/lib/contracts";

const BETTING_DECIMALS = 18; // adjust per token after deploy

export function useRoundCounter() {
  const { chainId } = useAccount();
  const controller = chainId ? getLaneControllerAddress(chainId) : undefined;

  return useReadContract({
    address: controller,
    abi: laneControllerAbi,
    functionName: "currentRoundId",
    query: {
      enabled: isDeployed(controller),
      refetchInterval: 10_000,
    },
  });
}

export function useRoundState(roundId: bigint | undefined) {
  const { chainId } = useAccount();
  const controller = chainId ? getLaneControllerAddress(chainId) : undefined;

  return useReadContract({
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

export function useRoundWinner(roundId: bigint | undefined) {
  const { chainId } = useAccount();
  const controller = chainId ? getLaneControllerAddress(chainId) : undefined;

  return useReadContract({
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

export function useLanePool(roundId: bigint | undefined, laneId: number) {
  const { chainId } = useAccount();
  const controller = chainId ? getLaneControllerAddress(chainId) : undefined;

  return useReadContract({
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

export function useTotalPrizePool(roundId: bigint | undefined) {
  const { chainId } = useAccount();
  const controller = chainId ? getLaneControllerAddress(chainId) : undefined;

  return useReadContract({
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

export function useLaneControllerActions() {
  const { chainId } = useAccount();
  const controller = chainId ? getLaneControllerAddress(chainId) : undefined;
  const deployment = chainId ? getDeploymentByChainId(chainId) : undefined;
  const bettingToken = deployment?.underlyingToken;

  const { writeContract, data: hash, isPending, error, reset } =
    useWriteContract();

  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  });

  const approveBettingToken = (amount: string) => {
    if (!bettingToken || !controller || !isDeployed(controller)) return;
    writeContract({
      address: bettingToken,
      abi: erc20Abi,
      functionName: "approve",
      args: [controller, parseUnits(amount, BETTING_DECIMALS)],
    });
  };

  const buyLaneTokens = (
    roundId: bigint,
    laneId: number,
    amount: string
  ) => {
    if (!controller || !isDeployed(controller)) return;
    writeContract({
      address: controller,
      abi: laneControllerAbi,
      functionName: "buyLaneTokens",
      args: [roundId, laneId, parseUnits(amount, BETTING_DECIMALS)],
    });
  };

  const claimPrize = (roundId: bigint) => {
    if (!controller || !isDeployed(controller)) return;
    writeContract({
      address: controller,
      abi: laneControllerAbi,
      functionName: "claimPrize",
      args: [roundId],
    });
  };

  return {
    approveBettingToken,
    buyLaneTokens,
    claimPrize,
    hash,
    isPending,
    isConfirming,
    isSuccess,
    error,
    reset,
    isDeployed: isDeployed(controller),
    bettingToken,
  };
}

/** RoundState enum: 0=Betting, 1=Racing, 2=Finished, 3=Settled */
export const RoundStateLabel: Record<number, string> = {
  0: "betting",
  1: "racing",
  2: "finished",
  3: "settled",
};
