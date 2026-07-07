"use client";

import { useCallback, useEffect, useRef, useState } from "react";
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
import { useTokenDecimals } from "@/hooks/useTokenDecimals";
import { useTokenAllowance } from "@/hooks/useTokenAllowance";

export type LaneControllerAction = "approve" | "buy" | "claim" | null;

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
  const { data: decimals } = useTokenDecimals(bettingToken);
  const { data: allowance, refetch: refetchAllowance } = useTokenAllowance(
    bettingToken,
    controller
  );

  const [pendingAction, setPendingAction] = useState<LaneControllerAction>(null);
  const [lastCompletedAction, setLastCompletedAction] =
    useState<LaneControllerAction>(null);

  const {
    writeContract,
    data: hash,
    isPending,
    error,
    reset: resetWrite,
  } = useWriteContract();

  const resetWriteRef = useRef(resetWrite);
  resetWriteRef.current = resetWrite;

  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  });

  useEffect(() => {
    if (!isSuccess || !pendingAction) return;
    setLastCompletedAction(pendingAction);
    void refetchAllowance();
    setPendingAction(null);
  }, [isSuccess, pendingAction, refetchAllowance]);

  const needsApproval = (amount: string): boolean => {
    if (decimals === undefined || allowance === undefined) return true;
    try {
      return allowance < parseUnits(amount, decimals);
    } catch {
      return true;
    }
  };

  const approveBettingToken = (amount: string) => {
    if (
      !bettingToken ||
      !controller ||
      !isDeployed(controller) ||
      decimals === undefined
    ) {
      return;
    }
    setPendingAction("approve");
    writeContract({
      address: bettingToken,
      abi: erc20Abi,
      functionName: "approve",
      args: [controller, parseUnits(amount, decimals)],
    });
  };

  const buyLaneTokens = (
    roundId: bigint,
    laneId: number,
    amount: string
  ) => {
    if (!controller || !isDeployed(controller) || decimals === undefined) {
      return;
    }
    setPendingAction("buy");
    writeContract({
      address: controller,
      abi: laneControllerAbi,
      functionName: "buyLaneTokens",
      args: [roundId, laneId, parseUnits(amount, decimals)],
    });
  };

  const claimPrize = (roundId: bigint) => {
    if (!controller || !isDeployed(controller)) return;
    setPendingAction("claim");
    writeContract({
      address: controller,
      abi: laneControllerAbi,
      functionName: "claimPrize",
      args: [roundId],
    });
  };

  const clearActionState = useCallback(() => {
    resetWriteRef.current();
    setPendingAction(null);
    setLastCompletedAction(null);
  }, []);

  return {
    approveBettingToken,
    buyLaneTokens,
    claimPrize,
    hash,
    isPending,
    isConfirming,
    isSuccess,
    error,
    reset: clearActionState,
    pendingAction,
    lastCompletedAction,
    needsApproval,
    allowance,
    isDeployed: isDeployed(controller),
    bettingToken,
    decimals,
  };
}

/** RoundState enum: 0=Betting, 1=Racing, 2=Finished, 3=Settled */
export const RoundStateLabel: Record<number, string> = {
  0: "betting",
  1: "racing",
  2: "finished",
  3: "settled",
};
