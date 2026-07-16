"use client";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { WagmiProvider, createConfig, http } from "wagmi";
import { injected } from "wagmi/connectors";
import { type ReactNode, useState } from "react";
import { SUPPORTED_CHAINS } from "@/lib/chains";

function rpcUrl(chainId: number, fallback?: string): string | undefined {
  const envByChain: Record<number, string | undefined> = {
    [SUPPORTED_CHAINS[0].id]: process.env.NEXT_PUBLIC_SEPOLIA_RPC,
    [SUPPORTED_CHAINS[1].id]: process.env.NEXT_PUBLIC_ARBITRUM_SEPOLIA_RPC,
    [SUPPORTED_CHAINS[2].id]: process.env.NEXT_PUBLIC_BASE_SEPOLIA_RPC,
  };
  return envByChain[chainId] ?? fallback;
}

const config = createConfig({
  chains: [...SUPPORTED_CHAINS],
  connectors: [injected()],
  transports: {
    [SUPPORTED_CHAINS[0].id]: http(rpcUrl(SUPPORTED_CHAINS[0].id)),
    [SUPPORTED_CHAINS[1].id]: http(rpcUrl(SUPPORTED_CHAINS[1].id)),
    [SUPPORTED_CHAINS[2].id]: http(rpcUrl(SUPPORTED_CHAINS[2].id)),
  },
  ssr: true,
});

export function Providers({ children }: { children: ReactNode }) {
  const [queryClient] = useState(() => new QueryClient());

  return (
    <WagmiProvider config={config}>
      <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
    </WagmiProvider>
  );
}
