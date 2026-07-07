"use client";

import type { LaneState } from "@/lib/lane-data";

interface LaneRaceVizProps {
  lanes: LaneState[];
  title?: string;
  compact?: boolean;
}

const LANE_COLORS = ["#00f5d4", "#ffb703", "#ff3366", "#c8f135", "#7b8cff"];

export function LaneRaceViz({
  lanes,
  title = "Live Race",
  compact = false,
}: LaneRaceVizProps) {
  const trackHeight = compact ? 40 : 56;
  const gap = compact ? 6 : 10;

  return (
    <div className="relative overflow-hidden rounded-sm border border-grid bg-asphalt-50 p-3 sm:p-5 lg:p-6">
      <div className="absolute inset-0 opacity-[0.03] bg-checkered pointer-events-none" />
      <div className="absolute top-0 right-0 w-24 sm:w-32 h-full bg-gradient-to-l from-neon-amber/5 to-transparent pointer-events-none" />

      <div className="relative flex items-center justify-between mb-3 sm:mb-4 gap-2">
        <h3 className="font-display text-xs sm:text-sm lg:text-base tracking-widest uppercase text-white/90 truncate">
          {title}
        </h3>
        <div className="flex items-center gap-1.5 sm:gap-2 shrink-0">
          <span className="h-2 w-2 rounded-full bg-neon-red animate-pulse" />
          <span className="font-mono text-[9px] sm:text-[10px] uppercase tracking-widest text-neon-red/80">
            Live
          </span>
        </div>
      </div>

      <div className="relative space-y-2 sm:space-y-3">
        {lanes.map((lane, i) => {
          const color = lane.color || LANE_COLORS[i % LANE_COLORS.length];
          const progressPct = Math.min(100, Math.max(0, lane.progress));

          return (
            <div
              key={lane.id}
              className="grid grid-cols-[2rem_1fr] sm:grid-cols-[2.5rem_1fr_auto] gap-2 sm:gap-3 items-center"
            >
              <span className="font-mono text-[10px] sm:text-xs text-white/40">
                L{lane.id}
              </span>

              <div
                className="relative rounded overflow-hidden border border-grid/80 bg-asphalt-200"
                style={{ height: trackHeight }}
              >
                <div
                  className="absolute inset-y-0 left-0 opacity-20"
                  style={{
                    width: `${progressPct}%`,
                    backgroundColor: color,
                  }}
                />
                <div
                  className="absolute top-1/2 -translate-y-1/2 h-0.5 w-[calc(100%-1rem)] left-2"
                  style={{
                    backgroundImage:
                      "repeating-linear-gradient(90deg, #2a3540 0 6px, transparent 6px 12px)",
                  }}
                />
                <div
                  className="absolute top-1/2 -translate-y-1/2 transition-all duration-700 ease-out"
                  style={{ left: `calc(${progressPct}% - 8px)` }}
                >
                  <div
                    className="w-0 h-0 border-y-[6px] border-y-transparent border-l-[10px]"
                    style={{ borderLeftColor: color }}
                  />
                </div>
                <div
                  className={`absolute right-0 top-0 bottom-0 w-1.5 bg-neon-amber ${
                    lane.finished ? "opacity-90 animate-finish-flash" : "opacity-30"
                  }`}
                />
              </div>

              <div className="col-span-2 sm:col-span-1 sm:text-right pl-8 sm:pl-0">
                <p
                  className="font-mono text-[10px] sm:text-xs truncate"
                  style={{ color }}
                >
                  {lane.label}
                </p>
                <p className="font-mono text-[9px] sm:text-[10px] text-white/40">
                  {lane.hopsCompleted}/{lane.maxHops} · {lane.latencySec}s
                </p>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
