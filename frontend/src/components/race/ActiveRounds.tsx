import Link from "next/link";
import { MOCK_ACTIVE_ROUNDS } from "@/lib/lane-data";

export function ActiveRounds() {
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

      <div className="grid gap-3 sm:grid-cols-2">
        {MOCK_ACTIVE_ROUNDS.map((round) => (
          <Link
            key={round.roundId}
            href={`/race/${round.roundId}`}
            className="group relative overflow-hidden border border-grid bg-asphalt-50 p-4 hover:border-neon-cyan/50 transition-colors"
          >
            <div className="absolute top-0 left-0 h-0.5 w-full bg-gradient-to-r from-neon-cyan via-transparent to-neon-amber opacity-0 group-hover:opacity-100 transition-opacity" />
            <div className="flex items-start justify-between">
              <div>
                <span className="font-mono text-[10px] uppercase tracking-widest text-white/40">
                  Round #{round.roundId}
                </span>
                <p className="mt-1 font-display text-2xl text-white">
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
                Betting closes{" "}
                {new Date(round.bettingEndsAt).toLocaleTimeString()}
              </p>
            )}
          </Link>
        ))}
      </div>
    </section>
  );
}

function StatusBadge({ status }: { status: string }) {
  const styles: Record<string, string> = {
    betting: "border-neon-amber text-neon-amber",
    racing: "border-neon-red text-neon-red",
    settled: "border-white/30 text-white/50",
  };

  return (
    <span
      className={`px-2 py-1 font-mono text-[10px] uppercase tracking-widest border ${styles[status] ?? ""}`}
    >
      {status}
    </span>
  );
}
