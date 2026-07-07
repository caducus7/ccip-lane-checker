"use client";

import { LeaderboardTable } from "@/components/leaderboard/LeaderboardTable";
import { useDeploymentStatus } from "@/hooks/useDeploymentStatus";

export function LeaderboardStats() {
  const { anyDeployed } = useDeploymentStatus();

  if (!anyDeployed) {
    return (
      <div className="grid gap-6 sm:grid-cols-3 mb-8">
        <StatCard label="Best Solo" value="—" sub="Awaiting deploy" />
        <StatCard label="Fastest Race" value="—" sub="Awaiting deploy" />
        <StatCard label="Total Races" value="0" sub="Testnet" />
      </div>
    );
  }

  return (
    <div className="grid gap-6 sm:grid-cols-3 mb-8">
      <StatCard label="Best Solo" value="186s" sub="5 hops" />
      <StatCard label="Fastest Race" value="201s" sub="Round #3" />
      <StatCard label="Total Races" value="12" sub="Testnet" />
    </div>
  );
}

function StatCard({
  label,
  value,
  sub,
}: {
  label: string;
  value: string;
  sub: string;
}) {
  return (
    <div className="border border-grid bg-asphalt-50 p-4">
      <p className="font-mono text-[10px] uppercase tracking-widest text-white/40">
        {label}
      </p>
      <p className="font-display text-3xl text-neon-cyan mt-1">{value}</p>
      <p className="font-mono text-xs text-white/40 mt-1">{sub}</p>
    </div>
  );
}
