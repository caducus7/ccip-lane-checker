"use client";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { WagmiProvider, createConfig, http } from "wagmi";
import { injected } from "wagmi/connectors";
import { arbitrumSepolia, sepolia } from "viem/chains";
import { type ReactNode, useState } from "react";

const config = createConfig({
  chains: [sepolia, arbitrumSepolia],
  connectors: [injected()],
  transports: {
    [sepolia.id]: http(),
    [arbitrumSepolia.id]: http(),
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
