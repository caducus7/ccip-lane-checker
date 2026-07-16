"use client";

import { useEffect, useRef } from "react";
import { useRouter } from "next/navigation";
import { useRaceOperator } from "@/hooks/useRaceOperator";
import {
  useHomeRoundCounter,
  useHomeRoundState,
} from "@/hooks/useHomeLaneController";
import { RoundStateLabel } from "@/hooks/useLaneController";
import { CHAIN_LABELS, type SupportedChainId } from "@/lib/chains";
import { TxFeedback } from "@/components/ui/TxFeedback";

interface OperatorPanelProps {
  /** When omitted or zero, only Create round is available (bootstrap). */
  roundId?: bigint;
}

export function OperatorPanel({ roundId }: OperatorPanelProps) {
  const router = useRouter();
  const { data: roundState } = useHomeRoundState(
    roundId !== undefined && roundId > 0n ? roundId : undefined,
  );
  const { data: currentRoundId, refetch: refetchRoundCounter } =
    useHomeRoundCounter();
  const status =
    roundState !== undefined
      ? (RoundStateLabel[Number(roundState)] ?? "unknown")
      : "unknown";
  const hasActiveRound = roundId !== undefined && roundId > 0n;

  const {
    isOwner,
    createRound,
    startRace,
    distributePrizes,
    sendHopsOnCurrentChain,
    switchToChain,
    pendingHops,
    hopsOnCurrentChain,
    hash,
    isPending,
    isConfirming,
    isSuccess,
    error,
    reset,
    pendingAction,
    chainId,
  } = useRaceOperator(hasActiveRound ? roundId : undefined);

  const navigatedForHash = useRef<string | undefined>(undefined);

  useEffect(() => {
    if (
      !isSuccess ||
      pendingAction !== "createRound" ||
      !hash ||
      navigatedForHash.current === hash
    ) {
      return;
    }
    navigatedForHash.current = hash;
    void (async () => {
      const result = await refetchRoundCounter();
      const nextId = result.data ?? currentRoundId;
      if (nextId !== undefined && nextId > 0n) {
        router.push(`/race/${nextId.toString()}`);
      }
    })();
  }, [
    isSuccess,
    pendingAction,
    hash,
    refetchRoundCounter,
    currentRoundId,
    router,
  ]);

  if (!isOwner) {
    return null;
  }

  const isTxBusy = isPending || isConfirming;
  const chainsNeeded = [
    ...new Set(pendingHops.map((h) => h.senderChainId)),
  ] as SupportedChainId[];

  return (
    <div className="border border-neon-amber/30 bg-neon-amber/5 p-4 sm:p-5 space-y-4">
      <div>
        <span className="font-mono text-[10px] uppercase tracking-[0.3em] text-neon-amber">
          Operator
        </span>
        <h2 className="font-display text-lg tracking-widest uppercase mt-1">
          Race <span className="text-neon-amber">Control</span>
        </h2>
        <p className="mt-1 font-mono text-[10px] text-white/45">
          Owner wallet — replaces CRE + manual smoke script for testnet.
        </p>
      </div>

      <div className="flex flex-wrap gap-2">
        <OperatorButton
          label="Create round"
          disabled={isTxBusy}
          onClick={createRound}
          busy={pendingAction === "createRound" && isTxBusy}
        />
        {hasActiveRound ? (
          <>
            <OperatorButton
              label="Start race"
              disabled={isTxBusy || status !== "betting"}
              onClick={startRace}
              busy={pendingAction === "startRace" && isTxBusy}
            />
            <OperatorButton
              label="Settle prizes"
              disabled={isTxBusy || status !== "finished"}
              onClick={distributePrizes}
              busy={pendingAction === "distributePrizes" && isTxBusy}
            />
          </>
        ) : null}
      </div>

      {hasActiveRound && (status === "racing" || status === "finished") && (
        <div className="space-y-3 border-t border-grid pt-3">
          <p className="font-mono text-[10px] uppercase tracking-widest text-white/40">
            CCIP hops ({pendingHops.length} pending)
          </p>

          {pendingHops.length === 0 ? (
            <p className="font-mono text-xs text-neon-lime/80">
              All lane hops complete on-chain.
            </p>
          ) : (
            <ul className="space-y-1.5 font-mono text-[10px] text-white/55">
              {pendingHops.map((hop) => (
                <li key={`${hop.laneId}-${hop.destSelector}`}>
                  Lane {hop.laneId} → send from{" "}
                  <span className="text-neon-cyan">
                    {CHAIN_LABELS[hop.senderChainId]}
                  </span>
                  {hop.senderChainId === chainId ? (
                    <span className="text-neon-lime"> (this chain)</span>
                  ) : null}
                </li>
              ))}
            </ul>
          )}

          <div className="flex flex-wrap gap-2">
            <OperatorButton
              label={
                hopsOnCurrentChain.length > 0
                  ? `Send hop (${hopsOnCurrentChain.length} on this chain)`
                  : "Send hop on this chain"
              }
              disabled={isTxBusy || hopsOnCurrentChain.length === 0}
              onClick={sendHopsOnCurrentChain}
              busy={pendingAction === "sendHop" && isTxBusy}
            />
            {chainsNeeded
              .filter((id) => id !== chainId)
              .map((id) => (
                <button
                  key={id}
                  type="button"
                  disabled={isTxBusy}
                  onClick={() => void switchToChain(id)}
                  className="px-3 py-2 font-mono text-[10px] uppercase tracking-wider border border-grid text-white/50 hover:border-neon-cyan hover:text-neon-cyan transition-colors disabled:opacity-40"
                >
                  Switch to {CHAIN_LABELS[id]}
                </button>
              ))}
          </div>

          <p className="font-mono text-[9px] text-white/35">
            After each hop, wait ~30–90s for CCIP delivery, then send the next
            hop on the chain shown above. Repeat until status is Finished.
          </p>
        </div>
      )}

      <TxFeedback
        hash={hash}
        error={error}
        isSuccess={isSuccess}
        successMessage={
          pendingAction === "createRound"
            ? "Round created — opening latest round"
            : pendingAction === "startRace"
              ? "Race started"
              : pendingAction === "distributePrizes"
                ? "Prizes distributed"
                : pendingAction === "sendHop"
                  ? "Hop sent — wait for CCIP then send again"
                  : undefined
        }
        onDismiss={reset}
      />
    </div>
  );
}

function OperatorButton({
  label,
  disabled,
  onClick,
  busy,
}: {
  label: string;
  disabled?: boolean;
  onClick: () => void;
  busy?: boolean;
}) {
  return (
    <button
      type="button"
      disabled={disabled}
      onClick={onClick}
      className="px-3 py-2 font-mono text-[10px] sm:text-xs uppercase tracking-wider border border-neon-amber/50 text-neon-amber hover:bg-neon-amber/10 transition-colors disabled:opacity-40"
    >
      {busy ? "Confirming…" : label}
    </button>
  );
}
