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
  hasLaneTokenDeployment,
  isDeployed,
  laneTokenAbi,
  resolveLaneToken,
} from "@/lib/contracts";
import { chainIdToSelector } from "@/lib/chains";
import type { SupportedChainId } from "@/lib/chains";
import { useTokenDecimals } from "@/hooks/useTokenDecimals";
import { useTokenAllowance } from "@/hooks/useTokenAllowance";

export type LaneTokenAction = "approve" | "deposit" | "start" | null;

export function useLaneTokenBalance() {
  const { address, chainId } = useAccount();
  const resolved = resolveLaneToken(chainId);

  return useReadContract({
    chainId: resolved.chainId,
    address: resolved.address,
    abi: laneTokenAbi,
    functionName: "s_balances",
    args: address ? [address] : undefined,
    query: {
      enabled: !!address && isDeployed(resolved.address),
    },
  });
}

export function useGameRound(gameId: bigint | undefined) {
  const { chainId } = useAccount();
  const resolved = resolveLaneToken(chainId);

  return useReadContract({
    chainId: resolved.chainId,
    address: resolved.address,
    abi: laneTokenAbi,
    functionName: "getGameRound",
    args: gameId !== undefined ? [gameId] : undefined,
    query: {
      enabled: gameId !== undefined && isDeployed(resolved.address),
      refetchInterval: 5_000,
    },
  });
}

export function useGameCounter() {
  const { chainId } = useAccount();
  const resolved = resolveLaneToken(chainId);

  return useReadContract({
    chainId: resolved.chainId,
    address: resolved.address,
    abi: laneTokenAbi,
    functionName: "s_gameCounter",
    query: {
      enabled: isDeployed(resolved.address),
      refetchInterval: 10_000,
    },
  });
}

export function useLaneTokenActions() {
  const { chainId, isConnected } = useAccount();
  const onChainToken =
    chainId !== undefined ? getLaneTokenAddress(chainId) : undefined;
  const readyOnCurrentChain = isDeployed(onChainToken);
  const contractsLive = hasLaneTokenDeployment();

  const deployment =
    chainId !== undefined ? getDeploymentByChainId(chainId) : undefined;
  const underlyingToken = deployment?.underlyingToken;
  const { data: decimals } = useTokenDecimals(
    underlyingToken,
    readyOnCurrentChain ? chainId : undefined,
  );
  const { data: allowance, refetch: refetchAllowance } = useTokenAllowance(
    underlyingToken,
    onChainToken,
    readyOnCurrentChain ? chainId : undefined,
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
      !onChainToken ||
      !readyOnCurrentChain ||
      decimals === undefined ||
      chainId === undefined
    ) {
      return;
    }
    setPendingAction("approve");
    writeContract({
      chainId,
      address: underlyingToken,
      abi: erc20Abi,
      functionName: "approve",
      args: [onChainToken, parseUnits(amount, decimals)],
    });
  };

  const deposit = (amount: string) => {
    if (
      !onChainToken ||
      !readyOnCurrentChain ||
      decimals === undefined ||
      chainId === undefined
    ) {
      return;
    }
    setPendingAction("deposit");
    writeContract({
      chainId,
      address: onChainToken,
      abi: laneTokenAbi,
      functionName: "deposit",
      args: [parseUnits(amount, decimals)],
    });
  };

  const startGame = (
    destChainId: SupportedChainId,
    amount: string,
    maxHops: number,
  ) => {
    if (
      !onChainToken ||
      !readyOnCurrentChain ||
      decimals === undefined ||
      chainId === undefined
    ) {
      return;
    }
    setPendingAction("start");
    writeContract({
      chainId,
      address: onChainToken,
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
    /** Manifest has LaneToken addresses (any chain). */
    contractsLive,
    /** Wallet is on a chain with a live LaneToken — required for writes. */
    readyOnCurrentChain,
    isConnected,
    chainId,
    decimals,
  };
}
