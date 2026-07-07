"use client";

import Link from "next/link";
import { formatEther } from "viem";
import {
  RoundStateLabel,
  useRoundCounter,
  useRoundState,
  useTotalPrizePool,
} from "@/hooks/useLaneController";
import { useDeploymentStatus } from "@/hooks/useDeploymentStatus";
import { formatUtcTime } from "@/lib/format-date";
import { MOCK_ACTIVE_ROUNDS } from "@/lib/lane-data";
import {
  DeploymentBanner,
  NoActiveRoundState,
} from "@/components/ui/EmptyState";
import { RoundCardSkeleton } from "@/components/ui/Skeleton";

export function ActiveRounds() {
  const { controllerDeployed } = useDeploymentStatus();
  const { data: currentRoundId, isLoading } = useRoundCounter();
  const { data: roundState } = useRoundState(currentRoundId);
  const { data: prizePool } = useTotalPrizePool(currentRoundId);

  const showDemo = !controllerDeployed;
  const hasActiveRound =
    controllerDeployed &&
    currentRoundId !== undefined &&
    currentRoundId > 0n;
  const status =
    roundState !== undefined
      ? (RoundStateLabel[Number(roundState)] ?? "betting")
      : "betting";

  return (
    <section className="space-y-4">
      <div className="flex items-end justify-between">
        <h2 className="font-display text-xl tracking-widest uppercase">
          Active <span className="text-neon-cyan">Rounds</span>
        </h2>
        <span className="font-mono text-[10px] text-white/40 uppercase tracking-widest">
          Parimutuel
        </span>
      </div>

      {showDemo && (
        <>
          <DeploymentBanner contractName="LaneController" />
          <div className="grid gap-3 sm:grid-cols-2">
            {MOCK_ACTIVE_ROUNDS.map((round) => (
              <RoundCard key={round.roundId} round={round} demo />
            ))}
          </div>
        </>
      )}

      {!showDemo && isLoading && (
        <div className="grid gap-3 sm:grid-cols-2">
          <RoundCardSkeleton />
          <RoundCardSkeleton />
        </div>
      )}

      {!showDemo && !isLoading && !hasActiveRound && <NoActiveRoundState />}

      {!showDemo && !isLoading && hasActiveRound && currentRoundId && (
        <div className="grid gap-3 sm:grid-cols-2">
          <RoundCard
            round={{
              roundId: Number(currentRoundId),
              totalPool:
                prizePool !== undefined && prizePool > 0n
                  ? `${formatEther(prizePool)} LINK`
                  : "—",
              laneCount: 3,
              status,
            }}
          />
        </div>
      )}
    </section>
  );
}

function RoundCard({
  round,
  demo = false,
}: {
  round: {
    roundId: number;
    totalPool: string;
    laneCount: number;
    status: string;
    bettingEndsAt?: string;
  };
  demo?: boolean;
}) {
  return (
    <Link
      href={`/race/${round.roundId}`}
      className="group relative overflow-hidden border border-grid bg-asphalt-50 p-4 hover:border-neon-cyan/50 transition-colors"
    >
      <div className="absolute top-0 left-0 h-0.5 w-full bg-gradient-to-r from-neon-cyan via-transparent to-neon-amber opacity-0 group-hover:opacity-100 transition-opacity" />
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0">
          <span className="font-mono text-[10px] uppercase tracking-widest text-white/40">
            Round #{round.roundId}
            {demo ? " (demo)" : ""}
          </span>
          <p className="mt-1 font-display text-2xl text-white truncate">
            {round.totalPool}
          </p>
          <p className="font-mono text-xs text-white/50">
            {round.laneCount} lanes
          </p>
        </div>
        <StatusBadge status={round.status} />
      </div>
      {round.bettingEndsAt && round.status === "betting" && (
        <p className="mt-3 font-mono text-[10px] text-neon-amber/80">
          Betting closes {formatUtcTime(round.bettingEndsAt)} UTC
        </p>
      )}
    </Link>
  );
}

function StatusBadge({ status }: { status: string }) {
  const styles: Record<string, string> = {
    betting: "border-neon-amber text-neon-amber",
    racing: "border-neon-red text-neon-red",
    finished: "border-neon-cyan text-neon-cyan",
    settled: "border-white/30 text-white/50",
  };

  return (
    <span
      className={`shrink-0 px-2 py-1 font-mono text-[10px] uppercase tracking-widest border ${styles[status] ?? "border-white/20 text-white/40"}`}
    >
      {status}
    </span>
  );
}
