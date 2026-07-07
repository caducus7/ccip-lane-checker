"use client";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { WagmiProvider, createConfig, http } from "wagmi";
import { injected } from "wagmi/connectors";
import { type ReactNode, useState } from "react";
import { SUPPORTED_CHAINS } from "@/lib/chains";

const config = createConfig({
  chains: [...SUPPORTED_CHAINS],
  connectors: [injected()],
  transports: {
    [SUPPORTED_CHAINS[0].id]: http(),
    [SUPPORTED_CHAINS[1].id]: http(),
    [SUPPORTED_CHAINS[2].id]: http(),
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
