import { LANE_BENCHMARKS, healthColor } from "@/lib/lane-data";

export function LaneHealthSummary() {
  const avgP50 =
    LANE_BENCHMARKS.reduce((s, l) => s + l.p50LatencySec, 0) /
    LANE_BENCHMARKS.length;
  const avgSuccess =
    LANE_BENCHMARKS.reduce((s, l) => s + l.successRate, 0) /
    LANE_BENCHMARKS.length;
  const degraded = LANE_BENCHMARKS.filter(
    (l) => l.health === "degraded" || l.health === "down"
  ).length;

  return (
    <section className="border border-grid bg-asphalt-50 p-5 sm:p-6">
      <h2 className="font-display text-lg tracking-widest uppercase mb-4">
        Lane <span className="text-neon-lime">Health</span>
      </h2>

      <div className="grid grid-cols-3 gap-4 mb-5">
        <Stat label="Avg p50" value={`${avgP50.toFixed(0)}s`} accent="cyan" />
        <Stat label="Success" value={`${avgSuccess.toFixed(1)}%`} accent="lime" />
        <Stat
          label="Alerts"
          value={degraded.toString()}
          accent={degraded > 0 ? "amber" : "cyan"}
        />
      </div>

      <ul className="space-y-2">
        {LANE_BENCHMARKS.slice(0, 3).map((lane) => (
          <li
            key={lane.id}
            className="flex items-center justify-between font-mono text-xs border-t border-grid/60 pt-2"
          >
            <span className="text-white/60 truncate pr-2">
              {lane.source.split(" ")[0]} → {lane.destination.split(" ")[0]}
            </span>
            <span className={`shrink-0 uppercase tracking-wider ${healthColor(lane.health)}`}>
              {lane.health}
            </span>
          </li>
        ))}
      </ul>
    </section>
  );
}

function Stat({
  label,
  value,
  accent,
}: {
  label: string;
  value: string;
  accent: "cyan" | "lime" | "amber";
}) {
  const colors = {
    cyan: "text-neon-cyan",
    lime: "text-neon-lime",
    amber: "text-neon-amber",
  };

  return (
    <div>
      <p className="font-mono text-[10px] uppercase tracking-widest text-white/40">
        {label}
      </p>
      <p className={`font-display text-2xl ${colors[accent]}`}>{value}</p>
    </div>
  );
}
