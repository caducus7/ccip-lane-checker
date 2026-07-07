"use client";

import { useState } from "react";
import { formatEther } from "viem";
import { arbitrumSepolia, sepolia } from "viem/chains";
import {
  useGameCounter,
  useLaneTokenActions,
  useLaneTokenBalance,
} from "@/hooks/useLaneToken";
import { HopProgress } from "@/components/solo/HopProgress";
import type { SupportedChainId } from "@/lib/chains";
import { CHAIN_LABELS } from "@/lib/chains";

export function SoloGamePanel() {
  const [amount, setAmount] = useState("0.01");
  const [maxHops, setMaxHops] = useState(5);
  const [destChain, setDestChain] = useState<SupportedChainId>(arbitrumSepolia.id);
  const [activeGameId, setActiveGameId] = useState<bigint | undefined>();

  const { data: balance } = useLaneTokenBalance();
  const { data: gameCounter } = useGameCounter();
  const { deposit, startGame, isPending, isConfirming, isSuccess, isDeployed, hash } =
    useLaneTokenActions();

  const handleStart = () => {
    startGame(destChain, amount, maxHops);
    if (gameCounter !== undefined) {
      setActiveGameId(gameCounter + 1n);
    }
  };

  return (
    <div className="grid gap-6 lg:grid-cols-2">
      <div className="border border-grid bg-asphalt-50 p-5 sm:p-6 space-y-5">
        <div>
          <h2 className="font-display text-xl tracking-widest uppercase">
            Start <span className="text-neon-cyan">Challenge</span>
          </h2>
          <p className="mt-2 font-mono text-xs text-white/50 leading-relaxed">
            Deposit tokens, then race across CCIP hops. VRF picks each next
            chain. Lowest total latency wins the standings.
          </p>
        </div>

        {!isDeployed && (
          <div className="border border-neon-amber/40 bg-neon-amber/5 px-4 py-3 font-mono text-xs text-neon-amber">
            LaneToken not deployed on this chain yet. Update{" "}
            <code className="text-neon-cyan">contracts/deployments/testnet.json</code>.
          </div>
        )}

        <div className="grid gap-4 sm:grid-cols-2">
          <label className="block">
            <span className="font-mono text-[10px] uppercase tracking-widest text-white/40">
              Deposit (ETH)
            </span>
            <input
              type="text"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              className="mt-1 w-full border border-grid bg-asphalt px-3 py-2 font-mono text-sm text-white focus:border-neon-cyan outline-none"
            />
          </label>
          <div className="flex items-end">
            <button
              type="button"
              disabled={!isDeployed || isPending || isConfirming}
              onClick={() => deposit(amount)}
              className="w-full py-2 font-mono text-xs uppercase tracking-widest border border-grid hover:border-neon-cyan hover:text-neon-cyan transition-colors disabled:opacity-40"
            >
              Deposit
            </button>
          </div>
        </div>

        <p className="font-mono text-xs text-white/40">
          Balance:{" "}
          <span className="text-neon-cyan">
            {balance !== undefined ? formatEther(balance) : "—"} ETH
          </span>
        </p>

        <hr className="border-grid" />

        <label className="block">
          <span className="font-mono text-[10px] uppercase tracking-widest text-white/40">
            First hop destination
          </span>
          <select
            value={destChain}
            onChange={(e) => setDestChain(Number(e.target.value) as SupportedChainId)}
            className="mt-1 w-full border border-grid bg-asphalt px-3 py-2 font-mono text-sm text-white focus:border-neon-cyan outline-none"
          >
            <option value={sepolia.id}>{CHAIN_LABELS[sepolia.id]}</option>
            <option value={arbitrumSepolia.id}>
              {CHAIN_LABELS[arbitrumSepolia.id]}
            </option>
          </select>
        </label>

        <label className="block">
          <span className="font-mono text-[10px] uppercase tracking-widest text-white/40">
            Max hops: {maxHops}
          </span>
          <input
            type="range"
            min={2}
            max={8}
            value={maxHops}
            onChange={(e) => setMaxHops(Number(e.target.value))}
            className="mt-2 w-full accent-neon-cyan"
          />
        </label>

        <button
          type="button"
          disabled={!isDeployed || isPending || isConfirming}
          onClick={handleStart}
          className="w-full py-3 font-mono text-sm uppercase tracking-[0.2em] bg-neon-cyan text-asphalt font-bold hover:shadow-[0_0_24px_rgba(0,245,212,0.35)] transition-shadow disabled:opacity-40"
        >
          {isPending || isConfirming ? "Confirming…" : "Start Race"}
        </button>

        {hash && (
          <p className="font-mono text-[10px] text-white/40 break-all">
            Tx: {hash}
          </p>
        )}
        {isSuccess && (
          <p className="font-mono text-xs text-neon-lime">
            Transaction confirmed. Watch hop progress →
          </p>
        )}
      </div>

      <HopProgress gameId={activeGameId ?? gameCounter} />
    </div>
  );
}
