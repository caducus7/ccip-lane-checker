import { LeaderboardTable } from "@/components/leaderboard/LeaderboardTable";

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
          CCIP hop latency. On-chain history once contracts are live.
        </p>
      </header>

      <div className="grid gap-6 sm:grid-cols-3 mb-8">
        <StatCard label="Best Solo" value="186s" sub="5 hops" />
        <StatCard label="Fastest Race" value="201s" sub="Round #3" />
        <StatCard label="Total Races" value="12" sub="Testnet" />
      </div>

      <LeaderboardTable />
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
