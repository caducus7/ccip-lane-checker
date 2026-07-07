"use client";

import { useEffect, useState } from "react";
import { formatEther } from "viem";
import {
  RoundStateLabel,
  useLaneControllerActions,
  useLanePool,
  useRoundCounter,
  useRoundState,
  useRoundWinner,
  useTotalPrizePool,
} from "@/hooks/useLaneController";
import { LaneRaceViz } from "@/components/race/LaneRaceViz";
import { demoLaneStates } from "@/lib/lane-data";
import { ccipExplorerHome } from "@/lib/ccip";
import {
  DeploymentBanner,
  EmptyState,
  NoActiveRoundState,
} from "@/components/ui/EmptyState";
import { RacePageSkeleton } from "@/components/ui/Skeleton";
import { TxFeedback } from "@/components/ui/TxFeedback";

interface BettingPanelProps {
  roundId: bigint;
}

const LANE_LABELS = ["SEP→ARB→SEP", "ARB→SEP→ARB", "SEP→BASE→SEP"];

export function BettingPanel({ roundId }: BettingPanelProps) {
  const [selectedLane, setSelectedLane] = useState(0);
  const [betAmount, setBetAmount] = useState("0.05");
  const [claimSuccess, setClaimSuccess] = useState(false);
  const [isClaiming, setIsClaiming] = useState(false);

  const { data: currentRoundId, isLoading: roundCounterLoading } =
    useRoundCounter();
  const {
    data: roundState,
    isLoading: roundStateLoading,
    isError: roundStateError,
  } = useRoundState(roundId);
  const { data: winnerLane } = useRoundWinner(roundId);
  const { data: totalPrizePool } = useTotalPrizePool(roundId);
  const { data: lane0 } = useLanePool(roundId, 0);
  const { data: lane1 } = useLanePool(roundId, 1);
  const { data: lane2 } = useLanePool(roundId, 2);

  const {
    approveBettingToken,
    buyLaneTokens,
    claimPrize,
    isPending,
    isConfirming,
    isSuccess,
    isDeployed,
    hash,
    error,
    reset,
    pendingAction,
    lastCompletedAction,
    needsApproval,
  } = useLaneControllerActions();

  const laneCount = 3;
  const status =
    roundState !== undefined
      ? (RoundStateLabel[Number(roundState)] ?? "betting")
      : isDeployed
        ? "betting"
        : "racing";
  const lanePools = [lane0, lane1, lane2];
  const totalPool =
    totalPrizePool ?? lanePools.reduce<bigint>((sum, p) => sum + (p ?? 0n), 0n);
  const demoLanes = demoLaneStates();
  const isRoundLoading = isDeployed && (roundStateLoading || roundCounterLoading);
  const roundNotFound =
    isDeployed &&
    currentRoundId !== undefined &&
    roundId > currentRoundId &&
    roundState === undefined;
  const canClaim = status === "settled" || status === "finished";
  const insufficientAllowance = needsApproval(betAmount);
  const isTxBusy = isPending || isConfirming;

  useEffect(() => {
    if (isSuccess && isClaiming) {
      setClaimSuccess(true);
      setIsClaiming(false);
    }
  }, [isSuccess, isClaiming]);

  useEffect(() => {
    setClaimSuccess(false);
    setIsClaiming(false);
    reset();
  }, [roundId, reset]);

  const vizLanes = lanePools.some((p) => p !== undefined && p > 0n)
    ? lanePools.map((pool, i) => ({
        id: i,
        label: LANE_LABELS[i] ?? `Lane ${i}`,
        color: demoLanes[i]?.color ?? "#00f5d4",
        progress: demoLanes[i]?.progress ?? 0,
        hopsCompleted: demoLanes[i]?.hopsCompleted ?? 0,
        maxHops: 5,
        latencySec: demoLanes[i]?.latencySec ?? 0,
        finished: demoLanes[i]?.finished ?? false,
      }))
    : demoLanes;

  if (isRoundLoading) {
    return <RacePageSkeleton />;
  }

  if (!isDeployed) {
    return (
      <div className="space-y-6">
        <RoundHeader roundId={roundId} status={status} />
        <DeploymentBanner contractName="LaneController" />
        <LaneRaceViz lanes={vizLanes} title="Multi-Lane Race (demo)" />
        <DemoBettingHint />
      </div>
    );
  }

  if (roundNotFound || roundStateError) {
    return (
      <div className="space-y-6">
        <RoundHeader roundId={roundId} status="unknown" />
        <EmptyState
          variant="error"
          title="Round not found"
          description={`Round #${roundId.toString()} does not exist on-chain yet. The current round is #${currentRoundId?.toString() ?? "—"}.`}
          action={{ label: "Back to home", href: "/" }}
        />
      </div>
    );
  }

  return (
    <div className="space-y-5 sm:space-y-6">
      <RoundHeader roundId={roundId} status={status} />

      {winnerLane !== undefined && canClaim && (
        <div className="border border-neon-lime/30 bg-neon-lime/5 px-4 py-3 font-mono text-xs text-neon-lime">
          Winner: Lane {winnerLane.toString()}
        </div>
      )}

      <LaneRaceViz lanes={vizLanes} title="Multi-Lane Race" />

      <div className="grid gap-5 sm:gap-6 lg:grid-cols-2">
        <div className="border border-grid bg-asphalt-50 p-4 sm:p-5 space-y-4">
          <h2 className="font-display text-lg sm:text-xl tracking-widest uppercase">
            Prize <span className="text-neon-amber">Pool</span>
          </h2>
          <p className="font-display text-3xl sm:text-4xl text-white break-all">
            {totalPool > 0n ? `${formatEther(totalPool)} LINK` : "—"}
          </p>
          <p className="font-mono text-[10px] sm:text-xs text-white/40">
            70% winner · 15% 2nd · 10% 3rd · 5% protocol
          </p>

          <ul className="space-y-2 pt-2 border-t border-grid">
            {vizLanes.map((lane, i) => (
              <li
                key={lane.id}
                className="flex justify-between gap-2 font-mono text-[10px] sm:text-xs"
              >
                <span style={{ color: lane.color }} className="truncate">
                  {lane.label}
                </span>
                <span className="text-white/50 shrink-0">
                  {lanePools[i] !== undefined && lanePools[i]! > 0n
                    ? `${formatEther(lanePools[i]!)} LINK`
                    : "—"}
                </span>
              </li>
            ))}
          </ul>
        </div>

        <div className="border border-grid bg-asphalt-50 p-4 sm:p-5 space-y-4">
          <h2 className="font-display text-lg sm:text-xl tracking-widest uppercase">
            Place <span className="text-neon-cyan">Bet</span>
          </h2>

          <div className="grid grid-cols-3 gap-1.5 sm:gap-2">
            {Array.from({ length: laneCount }).map((_, i) => (
              <button
                key={i}
                type="button"
                onClick={() => setSelectedLane(i)}
                className={`py-2.5 sm:py-3 font-mono text-[10px] sm:text-xs uppercase tracking-wider border transition-colors ${
                  selectedLane === i
                    ? "border-neon-cyan bg-neon-cyan/10 text-neon-cyan"
                    : "border-grid text-white/50 hover:border-white/30"
                }`}
              >
                Lane {i}
              </button>
            ))}
          </div>

          <label className="block">
            <span className="font-mono text-[10px] uppercase tracking-widest text-white/40">
              Amount (LINK)
            </span>
            <input
              type="text"
              inputMode="decimal"
              value={betAmount}
              onChange={(e) => setBetAmount(e.target.value)}
              disabled={status !== "betting" || isTxBusy}
              className="mt-1 w-full border border-grid bg-asphalt px-3 py-2.5 font-mono text-sm text-white focus:border-neon-cyan outline-none disabled:opacity-40"
            />
          </label>

          {status === "betting" && insufficientAllowance && (
            <button
              type="button"
              disabled={isTxBusy}
              onClick={() => approveBettingToken(betAmount)}
              className="w-full py-3 font-mono text-xs sm:text-sm uppercase tracking-[0.2em] border border-neon-amber text-neon-amber hover:bg-neon-amber/10 transition-colors disabled:opacity-40"
            >
              {pendingAction === "approve" && isTxBusy
                ? "Approving LINK…"
                : `Approve ${betAmount} LINK`}
            </button>
          )}

          {status === "betting" && !insufficientAllowance && (
            <p className="font-mono text-[10px] text-neon-lime/80 uppercase tracking-wider">
              ✓ LINK approved
            </p>
          )}

          <button
            type="button"
            disabled={
              status !== "betting" ||
              isTxBusy ||
              insufficientAllowance
            }
            onClick={() => buyLaneTokens(roundId, selectedLane, betAmount)}
            className="w-full py-3 font-mono text-xs sm:text-sm uppercase tracking-[0.2em] bg-neon-amber text-asphalt font-bold hover:shadow-[0_0_24px_rgba(255,183,3,0.35)] transition-shadow disabled:opacity-40"
          >
            {status !== "betting"
              ? "Betting Closed"
              : pendingAction === "buy" && isTxBusy
                ? "Placing bet…"
                : `Bet on Lane ${selectedLane}`}
          </button>

          {canClaim && (
            <div className="pt-2 border-t border-grid space-y-3">
              {claimSuccess ? (
                <div className="border border-neon-lime/40 bg-neon-lime/10 px-4 py-3">
                  <p className="font-mono text-xs text-neon-lime uppercase tracking-wider">
                    Prize claimed successfully
                  </p>
                  <p className="mt-1 font-mono text-[10px] text-white/50">
                    Funds sent to your wallet. Check your LINK balance.
                  </p>
                </div>
              ) : (
                <button
                  type="button"
                  disabled={isTxBusy}
                  onClick={() => {
                    setIsClaiming(true);
                    claimPrize(roundId);
                  }}
                  className="w-full py-3 font-mono text-xs sm:text-sm uppercase tracking-[0.2em] border border-neon-cyan text-neon-cyan hover:bg-neon-cyan/10 disabled:opacity-40 transition-colors"
                >
                  {isClaiming && isTxBusy
                    ? "Claiming prize…"
                    : "Claim Prize"}
                </button>
              )}
            </div>
          )}

          <TxFeedback
            hash={hash}
            error={error}
            isSuccess={isSuccess && lastCompletedAction !== "claim"}
            successMessage={
              lastCompletedAction === "approve"
                ? "LINK approved — place your bet"
                : lastCompletedAction === "buy"
                  ? "Bet placed on lane"
                  : undefined
            }
            onDismiss={reset}
          />
        </div>
      </div>
    </div>
  );
}

function RoundHeader({
  roundId,
  status,
}: {
  roundId: bigint;
  status: string;
}) {
  return (
    <div className="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
      <div>
        <span className="font-mono text-[10px] uppercase tracking-[0.3em] text-neon-amber">
          Parimutuel
        </span>
        <h1 className="font-display text-2xl sm:text-3xl lg:text-4xl tracking-wider uppercase mt-1">
          Round <span className="text-neon-cyan">#{roundId.toString()}</span>
        </h1>
      </div>
      <div className="flex items-center gap-3 self-start sm:self-auto">
        <StatusPill status={status} />
        <a
          href={ccipExplorerHome()}
          target="_blank"
          rel="noopener noreferrer"
          className="font-mono text-[10px] uppercase tracking-widest text-neon-cyan/60 hover:text-neon-cyan"
        >
          CCIP Explorer
        </a>
      </div>
    </div>
  );
}

function DemoBettingHint() {
  return (
    <EmptyState
      variant="info"
      title="Betting unavailable"
      description="Connect wallet on a deployed testnet chain to place parimutuel bets. Until then, explore the demo race visualization above."
    />
  );
}

function StatusPill({ status }: { status: string }) {
  const colors: Record<string, string> = {
    betting: "bg-neon-amber/20 text-neon-amber border-neon-amber/40",
    racing: "bg-neon-red/20 text-neon-red border-neon-red/40",
    finished: "bg-neon-cyan/20 text-neon-cyan border-neon-cyan/40",
    settled: "bg-white/10 text-white/50 border-white/20",
    unknown: "bg-white/5 text-white/40 border-white/20",
  };

  return (
    <span
      className={`px-3 py-1 font-mono text-[10px] uppercase tracking-widest border ${colors[status] ?? colors.unknown}`}
    >
      {status}
    </span>
  );
}