"use client";

import { useReadContract } from "wagmi";
import type { Address } from "viem";
import { erc20Abi, isDeployed } from "@/lib/contracts";

export function useTokenDecimals(
  tokenAddress: Address | undefined,
  chainId?: number,
) {
  return useReadContract({
    chainId,
    address: tokenAddress,
    abi: erc20Abi,
    functionName: "decimals",
    query: {
      enabled: isDeployed(tokenAddress),
      staleTime: 60_000,
    },
  });
}
