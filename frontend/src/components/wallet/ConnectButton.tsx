"use client";

import { useEffect, useState } from "react";
import { useAccount, useConnect, useDisconnect, useSwitchChain } from "wagmi";
import { SUPPORTED_CHAINS } from "@/lib/chains";

const connectButtonClass =
  "px-5 py-2.5 font-mono text-xs uppercase tracking-[0.2em] bg-neon-cyan text-asphalt font-bold hover:shadow-[0_0_20px_rgba(0,245,212,0.4)] transition-shadow disabled:opacity-50";

export function ConnectButton() {
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);

  const { address, isConnected, chain } = useAccount();
  const { connect, connectors, isPending } = useConnect();
  const { disconnect } = useDisconnect();
  const { switchChain } = useSwitchChain();

  const isSupported =
    chain && SUPPORTED_CHAINS.some((c) => c.id === chain.id);

  if (!mounted) {
    return (
      <button type="button" disabled className={connectButtonClass}>
        Connect Wallet
      </button>
    );
  }

  if (isConnected && address) {
    return (
      <div className="flex items-center gap-2">
        {!isSupported && switchChain && (
          <button
            type="button"
            onClick={() => switchChain({ chainId: SUPPORTED_CHAINS[0].id })}
            className="px-3 py-1.5 text-xs font-mono uppercase tracking-wider border border-neon-amber text-neon-amber hover:bg-neon-amber/10 transition-colors"
          >
            Switch Network
          </button>
        )}
        <span className="hidden sm:inline font-mono text-xs text-neon-cyan/80">
          {address.slice(0, 6)}…{address.slice(-4)}
        </span>
        <button
          type="button"
          onClick={() => disconnect()}
          className="px-4 py-2 font-mono text-xs uppercase tracking-widest border border-grid bg-asphalt-50 hover:border-neon-cyan hover:text-neon-cyan transition-all"
        >
          Disconnect
        </button>
      </div>
    );
  }

  const injected = connectors[0];

  return (
    <button
      type="button"
      disabled={!injected || isPending}
      onClick={() => injected && connect({ connector: injected })}
      className={connectButtonClass}
    >
      {isPending ? "Connecting…" : "Connect Wallet"}
    </button>
  );
}
