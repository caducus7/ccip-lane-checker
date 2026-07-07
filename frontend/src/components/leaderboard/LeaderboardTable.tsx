"use client";

import Link from "next/link";
import { MOCK_LEADERBOARD } from "@/lib/lane-data";
import { useDeploymentStatus } from "@/hooks/useDeploymentStatus";
import { DeploymentBanner } from "@/components/ui/EmptyState";

export function LeaderboardTable() {
  const { anyDeployed } = useDeploymentStatus();

  return (
    <div className="space-y-4">
      {!anyDeployed && (
        <DeploymentBanner contractName="Lane contracts" />
      )}

      {!anyDeployed ? (
        <div className="border border-grid bg-asphalt-50 p-8 text-center">
          <p className="font-mono text-sm text-white/40">
            On-chain leaderboard history will appear here once testnet
            contracts are deployed.
          </p>
          <Link
            href="/solo"
            className="inline-block mt-4 font-mono text-[10px] uppercase tracking-widest text-neon-cyan hover:underline"
          >
            Try solo challenge →
          </Link>
        </div>
      ) : (
        <LeaderboardGrid entries={MOCK_LEADERBOARD} />
      )}
    </div>
  );
}

function LeaderboardGrid({
  entries,
}: {
  entries: typeof MOCK_LEADERBOARD;
}) {
  return (
  <div className="overflow-x-auto border border-grid -mx-4 sm:mx-0">
      <table className="w-full min-w-[520px]">
        <thead>
          <tr className="border-b border-grid bg-asphalt-50 font-mono text-[10px] uppercase tracking-widest text-white/40">
            <th className="px-3 sm:px-4 py-3 text-left">Rank</th>
            <th className="px-3 sm:px-4 py-3 text-left">Player</th>
            <th className="px-3 sm:px-4 py-3 text-left">Mode</th>
            <th className="px-3 sm:px-4 py-3 text-right">Latency</th>
            <th className="px-3 sm:px-4 py-3 text-right hidden sm:table-cell">
              Hops
            </th>
            <th className="px-3 sm:px-4 py-3 text-right hidden md:table-cell">
              When
            </th>
          </tr>
        </thead>
        <tbody>
          {entries.map((entry) => (
            <tr
              key={`${entry.rank}-${entry.player}`}
              className="border-b border-grid/60 hover:bg-asphalt-50/50 transition-colors"
            >
              <td className="px-3 sm:px-4 py-3">
                <span
                  className={`font-display text-base sm:text-lg ${
                    entry.rank === 1
                      ? "text-neon-amber"
                      : entry.rank === 2
                        ? "text-white/70"
                        : entry.rank === 3
                          ? "text-neon-cyan/70"
                          : "text-white/40"
                  }`}
                >
                  {entry.rank.toString().padStart(2, "0")}
                </span>
              </td>
              <td className="px-3 sm:px-4 py-3 font-mono text-xs sm:text-sm text-white/80">
                {entry.player}
              </td>
              <td className="px-3 sm:px-4 py-3">
                <ModeBadge mode={entry.mode} roundId={entry.roundId} />
              </td>
              <td className="px-3 sm:px-4 py-3 text-right font-mono text-xs sm:text-sm text-neon-cyan">
                {entry.totalLatencySec}s
              </td>
              <td className="px-3 sm:px-4 py-3 text-right font-mono text-xs sm:text-sm text-white/50 hidden sm:table-cell">
                {entry.hops}
              </td>
              <td className="px-3 sm:px-4 py-3 text-right font-mono text-[10px] text-white/40 hidden md:table-cell">
                {new Date(entry.timestamp).toLocaleDateString()}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function ModeBadge({
  mode,
  roundId,
}: {
  mode: "solo" | "parimutuel";
  roundId?: number;
}) {
  if (mode === "parimutuel" && roundId) {
    return (
      <Link
        href={`/race/${roundId}`}
        className="font-mono text-[10px] uppercase tracking-wider text-neon-amber hover:underline"
      >
        Race #{roundId}
      </Link>
    );
  }

  return (
    <span className="font-mono text-[10px] uppercase tracking-wider text-neon-cyan/80">
      Solo
    </span>
  );
}
