"use client";

import Link from "next/link";
import { ActiveRounds } from "@/components/race/ActiveRounds";
import { LaneHealthSummary } from "@/components/race/LaneHealthSummary";
import { FeaturedRace } from "@/components/race/FeaturedRace";
import { OperatorPanel } from "@/components/race/OperatorPanel";
import { useDeploymentStatus } from "@/hooks/useDeploymentStatus";
import { useRoundCounter } from "@/hooks/useLaneController";

export function HomeRaceSection() {
  const { anyDeployed } = useDeploymentStatus();
  const { data: currentRoundId } = useRoundCounter();
  const hasRound = !!currentRoundId && currentRoundId > 0n;

  const joinHref =
    anyDeployed && hasRound ? `/race/${currentRoundId.toString()}` : "/race/1";

  return (
    <div className="space-y-12">
      <section className="relative">
        <div className="absolute -left-4 top-0 h-full w-1 bg-gradient-to-b from-neon-cyan via-neon-amber to-transparent opacity-60" />
        <p className="font-mono text-[10px] uppercase tracking-[0.4em] text-neon-cyan/70 mb-3">
          Cross-chain latency racing
        </p>
        <h1 className="font-display text-4xl sm:text-5xl lg:text-6xl tracking-wider uppercase leading-tight">
          Bet on the
          <br />
          <span className="text-neon-cyan">fastest lane</span>
        </h1>
        <p className="mt-4 max-w-xl font-mono text-sm text-white/50 leading-relaxed">
          CCIP Lane Checker turns cross-chain messaging into a race. Solo
          challenge your latency or join parimutuel pools — all settled on-chain
          with verifiable VRF hops.
        </p>
        <div className="mt-8 flex flex-wrap gap-3">
          <Link
            href="/solo"
            className="px-6 py-3 font-mono text-xs uppercase tracking-[0.2em] bg-neon-cyan text-asphalt font-bold hover:shadow-[0_0_24px_rgba(0,245,212,0.35)] transition-shadow"
          >
            Solo Challenge
          </Link>
          <Link
            href={joinHref}
            className="px-6 py-3 font-mono text-xs uppercase tracking-[0.2em] border border-neon-amber text-neon-amber hover:bg-neon-amber/10 transition-colors"
          >
            Join Race
          </Link>
          <Link
            href="/lanes"
            className="px-6 py-3 font-mono text-xs uppercase tracking-[0.2em] border border-grid text-white/50 hover:text-white hover:border-white/30 transition-colors"
          >
            Lane Benchmarks
          </Link>
        </div>
      </section>

      {anyDeployed && !hasRound ? <OperatorPanel /> : null}

      <FeaturedRace />

      <div className="grid gap-8 lg:grid-cols-3">
        <div className="lg:col-span-2">
          <ActiveRounds />
        </div>
        <LaneHealthSummary />
      </div>
    </div>
  );
}
