"use client";

import { useAccount, useReadContract } from "wagmi";
import type { Address } from "viem";
import { erc20Abi, isDeployed } from "@/lib/contracts";

export function useTokenAllowance(
  token: Address | undefined,
  spender: Address | undefined
) {
  const { address: owner } = useAccount();

  return useReadContract({
    address: token,
    abi: erc20Abi,
    functionName: "allowance",
    args: owner && spender ? [owner, spender] : undefined,
    query: {
      enabled: !!owner && isDeployed(token) && isDeployed(spender),
      refetchInterval: 8_000,
    },
  });
}
