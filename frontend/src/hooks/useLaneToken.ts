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
  getLaneTokenAddress,
  isDeployed,
  laneTokenAbi,
} from "@/lib/contracts";
import { chainIdToSelector } from "@/lib/chains";
import type { SupportedChainId } from "@/lib/chains";
import { useTokenDecimals } from "@/hooks/useTokenDecimals";
import { useTokenAllowance } from "@/hooks/useTokenAllowance";

export type LaneTokenAction = "approve" | "deposit" | "start" | null;

export function useLaneTokenBalance() {
  const { address, chainId } = useAccount();
  const laneToken = chainId ? getLaneTokenAddress(chainId) : undefined;

  return useReadContract({
    address: laneToken,
    abi: laneTokenAbi,
    functionName: "s_balances",
    args: address ? [address] : undefined,
    query: {
      enabled: !!address && isDeployed(laneToken),
    },
  });
}

export function useGameRound(gameId: bigint | undefined) {
  const { chainId } = useAccount();
  const laneToken = chainId ? getLaneTokenAddress(chainId) : undefined;

  return useReadContract({
    address: laneToken,
    abi: laneTokenAbi,
    functionName: "getGameRound",
    args: gameId !== undefined ? [gameId] : undefined,
    query: {
      enabled: gameId !== undefined && isDeployed(laneToken),
      refetchInterval: 5_000,
    },
  });
}

export function useGameCounter() {
  const { chainId } = useAccount();
  const laneToken = chainId ? getLaneTokenAddress(chainId) : undefined;

  return useReadContract({
    address: laneToken,
    abi: laneTokenAbi,
    functionName: "s_gameCounter",
    query: {
      enabled: isDeployed(laneToken),
      refetchInterval: 10_000,
    },
  });
}

export function useLaneTokenActions() {
  const { chainId } = useAccount();
  const laneToken = chainId ? getLaneTokenAddress(chainId) : undefined;
  const deployment = chainId ? getDeploymentByChainId(chainId) : undefined;
  const underlyingToken = deployment?.underlyingToken;
  const { data: decimals } = useTokenDecimals(underlyingToken);
  const { data: allowance, refetch: refetchAllowance } = useTokenAllowance(
    underlyingToken,
    laneToken
  );

  const [pendingAction, setPendingAction] = useState<LaneTokenAction>(null);
  const [lastCompletedAction, setLastCompletedAction] =
    useState<LaneTokenAction>(null);

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

  const approveUnderlying = (amount: string) => {
    if (
      !underlyingToken ||
      !laneToken ||
      !isDeployed(laneToken) ||
      decimals === undefined
    ) {
      return;
    }
    setPendingAction("approve");
    writeContract({
      address: underlyingToken,
      abi: erc20Abi,
      functionName: "approve",
      args: [laneToken, parseUnits(amount, decimals)],
    });
  };

  const deposit = (amount: string) => {
    if (!laneToken || !isDeployed(laneToken) || decimals === undefined) return;
    setPendingAction("deposit");
    writeContract({
      address: laneToken,
      abi: laneTokenAbi,
      functionName: "deposit",
      args: [parseUnits(amount, decimals)],
    });
  };

  const startGame = (
    destChainId: SupportedChainId,
    amount: string,
    maxHops: number
  ) => {
    if (!laneToken || !isDeployed(laneToken) || decimals === undefined) return;
    setPendingAction("start");
    writeContract({
      address: laneToken,
      abi: laneTokenAbi,
      functionName: "startGame",
      args: [
        chainIdToSelector(destChainId),
        parseUnits(amount, decimals),
        maxHops,
      ],
    });
  };

  const clearActionState = useCallback(() => {
    resetWriteRef.current();
    setPendingAction(null);
    setLastCompletedAction(null);
  }, []);

  return {
    approveUnderlying,
    deposit,
    startGame,
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
    isDeployed: isDeployed(laneToken),
    decimals,
  };
}
