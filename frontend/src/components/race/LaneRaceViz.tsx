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
  const trackHeight = compact ? 48 : 64;
  const gap = compact ? 8 : 14;
  const totalHeight = lanes.length * (trackHeight + gap);

  return (
    <div className="relative overflow-hidden rounded-sm border border-grid bg-asphalt-50 p-4 sm:p-6">
      <div className="absolute inset-0 opacity-[0.03] bg-checkered bg-checkered pointer-events-none" />
      <div className="absolute top-0 right-0 w-32 h-full bg-gradient-to-l from-neon-amber/5 to-transparent pointer-events-none" />

      <div className="relative flex items-center justify-between mb-4">
        <h3 className="font-display text-sm sm:text-base tracking-widest uppercase text-white/90">
          {title}
        </h3>
        <div className="flex items-center gap-2">
          <span className="h-2 w-2 rounded-full bg-neon-red animate-pulse" />
          <span className="font-mono text-[10px] uppercase tracking-widest text-neon-red/80">
            Live
          </span>
        </div>
      </div>

      <svg
        viewBox={`0 0 800 ${totalHeight + 20}`}
        className="w-full h-auto"
        role="img"
        aria-label="Lane race visualization"
      >
        <defs>
          <pattern
            id="track-dash"
            width="12"
            height="4"
            patternUnits="userSpaceOnUse"
          >
            <rect width="6" height="2" fill="#2a3540" />
          </pattern>
          <filter id="glow">
            <feGaussianBlur stdDeviation="2" result="blur" />
            <feMerge>
              <feMergeNode in="blur" />
              <feMergeNode in="SourceGraphic" />
            </feMerge>
          </filter>
        </defs>

        {lanes.map((lane, i) => {
          const y = i * (trackHeight + gap) + 10;
          const trackWidth = 720;
          const startX = 40;
          const racerX =
            startX + (lane.progress / 100) * (trackWidth - 40);
          const color = lane.color || LANE_COLORS[i % LANE_COLORS.length];

          return (
            <g key={lane.id}>
              <text
                x={4}
                y={y + trackHeight / 2 + 4}
                className="fill-white/40"
                fontSize={compact ? 9 : 11}
                fontFamily="var(--font-mono)"
              >
                L{lane.id}
              </text>

              <rect
                x={startX}
                y={y}
                width={trackWidth}
                height={trackHeight}
                rx={4}
                fill="#0f1216"
                stroke="#1e2832"
                strokeWidth={1}
              />
              <rect
                x={startX + 8}
                y={y + trackHeight / 2 - 1}
                width={trackWidth - 16}
                height={2}
                fill="url(#track-dash)"
              />

              {Array.from({ length: lane.maxHops }).map((_, hop) => {
                const hopX =
                  startX +
                  20 +
                  ((hop + 1) / (lane.maxHops + 1)) * (trackWidth - 40);
                const done = hop < lane.hopsCompleted;
                return (
                  <g key={hop}>
                    <line
                      x1={hopX}
                      y1={y + 6}
                      x2={hopX}
                      y2={y + trackHeight - 6}
                      stroke={done ? color : "#2a3540"}
                      strokeWidth={1}
                      strokeDasharray={done ? "0" : "4 4"}
                      opacity={done ? 0.8 : 0.4}
                    />
                    <circle
                      cx={hopX}
                      cy={y + trackHeight / 2}
                      r={4}
                      fill={done ? color : "#1a1e24"}
                      stroke={done ? color : "#3a4550"}
                      strokeWidth={1}
                    />
                  </g>
                );
              })}

              <rect
                x={startX + trackWidth - 8}
                y={y}
                width={8}
                height={trackHeight}
                fill="#ffb703"
                opacity={lane.finished ? 0.9 : 0.3}
                className={lane.finished ? "animate-finish-flash" : ""}
              />

              <g filter="url(#glow)" transform={`translate(${racerX}, ${y + trackHeight / 2})`}>
                <polygon
                  points="-10,-6 14,0 -10,6"
                  fill={color}
                  className="transition-all duration-700 ease-out"
                />
                <circle cx={-4} cy={0} r={2} fill="#fff" opacity={0.8} />
              </g>

              <text
                x={startX + trackWidth + 12}
                y={y + trackHeight / 2 - 6}
                fill={color}
                fontSize={10}
                fontFamily="var(--font-mono)"
              >
                {lane.label}
              </text>
              <text
                x={startX + trackWidth + 12}
                y={y + trackHeight / 2 + 10}
                fill="#ffffff60"
                fontSize={9}
                fontFamily="var(--font-mono)"
              >
                {lane.hopsCompleted}/{lane.maxHops} · {lane.latencySec}s
              </text>
            </g>
          );
        })}
      </svg>
    </div>
  );
}
