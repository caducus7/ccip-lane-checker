import Link from "next/link";
import { MOCK_LEADERBOARD } from "@/lib/lane-data";

export function LeaderboardTable() {
  return (
    <div className="overflow-x-auto border border-grid">
      <table className="w-full min-w-[640px]">
        <thead>
          <tr className="border-b border-grid bg-asphalt-50 font-mono text-[10px] uppercase tracking-widest text-white/40">
            <th className="px-4 py-3 text-left">Rank</th>
            <th className="px-4 py-3 text-left">Player</th>
            <th className="px-4 py-3 text-left">Mode</th>
            <th className="px-4 py-3 text-right">Latency</th>
            <th className="px-4 py-3 text-right">Hops</th>
            <th className="px-4 py-3 text-right">When</th>
          </tr>
        </thead>
        <tbody>
          {MOCK_LEADERBOARD.map((entry) => (
            <tr
              key={`${entry.rank}-${entry.player}`}
              className="border-b border-grid/60 hover:bg-asphalt-50/50 transition-colors"
            >
              <td className="px-4 py-3">
                <span
                  className={`font-display text-lg ${
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
              <td className="px-4 py-3 font-mono text-sm text-white/80">
                {entry.player}
              </td>
              <td className="px-4 py-3">
                <ModeBadge mode={entry.mode} roundId={entry.roundId} />
              </td>
              <td className="px-4 py-3 text-right font-mono text-sm text-neon-cyan">
                {entry.totalLatencySec}s
              </td>
              <td className="px-4 py-3 text-right font-mono text-sm text-white/50">
                {entry.hops}
              </td>
              <td className="px-4 py-3 text-right font-mono text-[10px] text-white/40">
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
