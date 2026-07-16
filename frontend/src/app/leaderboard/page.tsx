import { LeaderboardTable } from "@/components/leaderboard/LeaderboardTable";
import { LeaderboardStats } from "@/components/leaderboard/LeaderboardStats";

export default function LeaderboardPage() {
  return (
    <div className="space-y-8">
      <header>
        <span className="font-mono text-[10px] uppercase tracking-[0.3em] text-neon-amber">
          Hall of Fame
        </span>
        <h1 className="font-display text-3xl sm:text-4xl tracking-wider uppercase mt-1">
          <span className="text-neon-amber">Standings</span>
        </h1>
        <p className="mt-2 font-mono text-sm text-white/50 max-w-2xl">
          Solo challenge finishes and parimutuel race winners ranked by total
          CCIP hop latency. On-chain history expands as rounds complete.
        </p>
      </header>

      <LeaderboardStats />

      <LeaderboardTable />
    </div>
  );
}
