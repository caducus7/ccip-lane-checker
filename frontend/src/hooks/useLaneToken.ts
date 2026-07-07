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
  getLaneTokenAddress,
  isDeployed,
  laneTokenAbi,
} from "@/lib/contracts";
import { chainIdToSelector } from "@/lib/chains";
import type { SupportedChainId } from "@/lib/chains";
import { useTokenDecimals } from "@/hooks/useTokenDecimals";

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
  const { writeContract, data: hash, isPending, error, reset } =
    useWriteContract();

  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  });

  const approveUnderlying = (amount: string) => {
    if (
      !underlyingToken ||
      !laneToken ||
      !isDeployed(laneToken) ||
      decimals === undefined
    ) {
      return;
    }
    writeContract({
      address: underlyingToken,
      abi: erc20Abi,
      functionName: "approve",
      args: [laneToken, parseUnits(amount, decimals)],
    });
  };

  const deposit = (amount: string) => {
    if (!laneToken || !isDeployed(laneToken) || decimals === undefined) return;
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

  return {
    approveUnderlying,
    deposit,
    startGame,
    hash,
    isPending,
    isConfirming,
    isSuccess,
    error,
    reset,
    isDeployed: isDeployed(laneToken),
    decimals,
  };
}
