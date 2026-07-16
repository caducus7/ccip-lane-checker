"use client";

import { useState } from "react";
import { formatEther } from "viem";
import { useSwitchChain } from "wagmi";
import {
  useGameCounter,
  useLaneTokenActions,
  useLaneTokenBalance,
} from "@/hooks/useLaneToken";
import { HopProgress } from "@/components/solo/HopProgress";
import type { SupportedChainId } from "@/lib/chains";
import { CHAIN_LABELS, SUPPORTED_CHAINS } from "@/lib/chains";
import { HOME_CHAIN_ID } from "@/lib/contracts";
import { EmptyState } from "@/components/ui/EmptyState";
import { TxFeedback } from "@/components/ui/TxFeedback";

export function SoloGamePanel() {
  const [amount, setAmount] = useState("0.01");
  const [maxHops, setMaxHops] = useState(5);
  const [destChain, setDestChain] = useState<SupportedChainId>(
    SUPPORTED_CHAINS[1].id,
  );
  const [activeGameId, setActiveGameId] = useState<bigint | undefined>();
  const { switchChainAsync } = useSwitchChain();

  const { data: balance } = useLaneTokenBalance();
  const { data: gameCounter } = useGameCounter();
  const {
    approveUnderlying,
    deposit,
    startGame,
    isPending,
    isConfirming,
    isSuccess,
    contractsLive,
    readyOnCurrentChain,
    isConnected,
    chainId,
    hash,
    error,
    reset,
    pendingAction,
    lastCompletedAction,
    needsApproval,
  } = useLaneTokenActions();

  const isTxBusy = isPending || isConfirming;
  const canWrite = contractsLive && readyOnCurrentChain;
  const insufficientAllowance = needsApproval(amount);
  const needsDepositApproval = insufficientAllowance;

  const handleStart = () => {
    startGame(destChain, amount, maxHops);
    if (gameCounter !== undefined) {
      setActiveGameId(gameCounter + 1n);
    }
  };

  return (
    <div className="grid gap-5 sm:gap-6 lg:grid-cols-2">
      <div className="border border-grid bg-asphalt-50 p-4 sm:p-5 lg:p-6 space-y-5">
        <div>
          <h2 className="font-display text-lg sm:text-xl tracking-widest uppercase">
            Start <span className="text-neon-cyan">Challenge</span>
          </h2>
          <p className="mt-2 font-mono text-xs text-white/50 leading-relaxed">
            Deposit tokens, then race across CCIP hops. VRF picks each next
            chain. Lowest total latency wins the standings.
          </p>
        </div>

        {!contractsLive && (
          <EmptyState
            variant="warning"
            title="LaneToken not available"
            description="No live LaneToken address in contracts/deployments/testnet.json. Fill addresses after deploy, or set NEXT_PUBLIC_* overrides."
            action={{ label: "View benchmarks", href: "/lanes" }}
          />
        )}

        {contractsLive && !isConnected && (
          <EmptyState
            variant="info"
            title="Connect wallet"
            description="Connect on Ethereum Sepolia, Arbitrum Sepolia, or Base Sepolia to deposit LINK and start a solo challenge."
          />
        )}

        {contractsLive && isConnected && !readyOnCurrentChain && (
          <div className="border border-neon-amber/40 bg-neon-amber/10 px-4 py-3 flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
            <p className="font-mono text-xs text-neon-amber">
              Switch to a supported testnet to use Solo (you are on chain{" "}
              {chainId ?? "—"}).
            </p>
            <button
              type="button"
              onClick={() => void switchChainAsync({ chainId: HOME_CHAIN_ID })}
              className="shrink-0 px-3 py-2 font-mono text-[10px] uppercase tracking-wider border border-neon-amber text-neon-amber hover:bg-neon-amber/10"
            >
              Switch to {CHAIN_LABELS[HOME_CHAIN_ID as SupportedChainId]}
            </button>
          </div>
        )}

        <div className="space-y-3">
          <label className="block">
            <span className="font-mono text-[10px] uppercase tracking-widest text-white/40">
              Deposit amount (LINK)
            </span>
            <input
              type="text"
              inputMode="decimal"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              disabled={!canWrite || isTxBusy}
              className="mt-1 w-full border border-grid bg-asphalt px-3 py-2.5 font-mono text-sm text-white focus:border-neon-cyan outline-none disabled:opacity-40"
            />
          </label>

          {canWrite && needsDepositApproval && (
            <button
              type="button"
              disabled={isTxBusy}
              onClick={() => approveUnderlying(amount)}
              className="w-full py-3 font-mono text-xs sm:text-sm uppercase tracking-[0.2em] border border-neon-amber text-neon-amber hover:bg-neon-amber/10 transition-colors disabled:opacity-40"
            >
              {pendingAction === "approve" && isTxBusy
                ? "Approving LINK…"
                : `Approve ${amount} LINK to deposit`}
            </button>
          )}

          {canWrite && !needsDepositApproval && (
            <p className="font-mono text-[10px] text-neon-lime/80 uppercase tracking-wider">
              ✓ LINK approved for deposit
            </p>
          )}

          <button
            type="button"
            disabled={!canWrite || isTxBusy || needsDepositApproval}
            onClick={() => deposit(amount)}
            className="w-full py-2.5 font-mono text-xs uppercase tracking-widest border border-grid hover:border-neon-cyan hover:text-neon-cyan transition-colors disabled:opacity-40"
          >
            {pendingAction === "deposit" && isTxBusy
              ? "Depositing…"
              : "Deposit to LaneToken"}
          </button>
        </div>

        <p className="font-mono text-xs text-white/40">
          Balance:{" "}
          <span className="text-neon-cyan">
            {balance !== undefined ? formatEther(balance) : "—"} LINK
          </span>
        </p>

        <hr className="border-grid" />

        <label className="block">
          <span className="font-mono text-[10px] uppercase tracking-widest text-white/40">
            First hop destination
          </span>
          <select
            value={destChain}
            onChange={(e) =>
              setDestChain(Number(e.target.value) as SupportedChainId)
            }
            disabled={!canWrite}
            className="mt-1 w-full border border-grid bg-asphalt px-3 py-2.5 font-mono text-sm text-white focus:border-neon-cyan outline-none disabled:opacity-40"
          >
            {SUPPORTED_CHAINS.map((chain) => (
              <option key={chain.id} value={chain.id}>
                {CHAIN_LABELS[chain.id as SupportedChainId]}
              </option>
            ))}
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
            disabled={!canWrite}
            className="mt-2 w-full accent-neon-cyan disabled:opacity-40"
          />
        </label>

        <button
          type="button"
          disabled={!canWrite || isTxBusy}
          onClick={handleStart}
          className="w-full py-3 font-mono text-xs sm:text-sm uppercase tracking-[0.2em] bg-neon-cyan text-asphalt font-bold hover:shadow-[0_0_24px_rgba(0,245,212,0.35)] transition-shadow disabled:opacity-40"
        >
          {pendingAction === "start" && isTxBusy
            ? "Starting race…"
            : "Start Race"}
        </button>

        <TxFeedback
          hash={hash}
          error={error}
          isSuccess={isSuccess}
          successMessage={
            lastCompletedAction === "approve"
              ? "LINK approved — ready to deposit"
              : lastCompletedAction === "deposit"
                ? "Deposit confirmed"
                : lastCompletedAction === "start"
                  ? "Race started — watch hop progress →"
                  : undefined
          }
          onDismiss={reset}
        />
      </div>

      <HopProgress gameId={activeGameId ?? gameCounter} />
    </div>
  );
}
