"use client";

import { useEffect, useState } from "react";

import type { BenchmarkSnapshot } from "@/lib/benchmark-types";
import {
  LANE_BENCHMARKS,
  healthColor,
  type LaneBenchmark,
} from "@/lib/lane-data";
import { ccipExplorerHome } from "@/lib/ccip";
import { snapshotToLaneBenchmarks } from "@/lib/snapshot-to-lanes";
import { formatUtcDateTime } from "@/lib/format-date";

type DataSource = "loading" | "cache" | "static";

export function LaneBenchmarkDashboard() {
  const [lanes, setLanes] = useState<LaneBenchmark[]>(LANE_BENCHMARKS);
  const [source, setSource] = useState<DataSource>("loading");
  const [fetchedAt, setFetchedAt] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;

    async function loadBenchmarks() {
      try {
        const res = await fetch("/api/lanes", { cache: "no-store" });
        if (!res.ok) throw new Error(`HTTP ${res.status}`);

        const data = (await res.json()) as {
          snapshot: BenchmarkSnapshot | null;
          source: "cache" | "empty";
        };

        if (cancelled) return;

        if (data.snapshot?.lanes?.length) {
          setLanes(snapshotToLaneBenchmarks(data.snapshot));
          setFetchedAt(data.snapshot.fetchedAt);
          setSource("cache");
        } else {
          setLanes(LANE_BENCHMARKS);
          setSource("static");
        }
      } catch {
        if (!cancelled) {
          setLanes(LANE_BENCHMARKS);
          setSource("static");
        }
      }
    }

    void loadBenchmarks();
    return () => {
      cancelled = true;
    };
  }, []);

  const sourceLabel =
    source === "loading"
      ? "Loading lane metrics…"
      : source === "cache"
        ? `Live CCIP cache${fetchedAt ? ` · ${formatTimestamp(fetchedAt)}` : ""}`
        : "Static placeholder — CRE lane-benchmark will POST to /api/lanes";

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row sm:items-end sm:justify-between gap-4">
        <div>
          <span className="font-mono text-[10px] uppercase tracking-[0.3em] text-neon-lime">
            CCIP Metrics
          </span>
          <h1 className="font-display text-3xl sm:text-4xl tracking-wider uppercase mt-1">
            Lane <span className="text-neon-cyan">Benchmarks</span>
          </h1>
        </div>
        <p className="font-mono text-xs text-white/40 max-w-sm">{sourceLabel}</p>
      </div>

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        {lanes.map((lane) => (
          <LaneCard key={lane.id} lane={lane} />
        ))}
      </div>

      <HeatmapTable lanes={lanes} />
    </div>
  );
}

function formatTimestamp(iso: string): string {
  try {
    return formatUtcDateTime(iso);
  } catch {
    return iso;
  }
}

function LaneCard({ lane }: { lane: LaneBenchmark }) {
  const barWidth = Math.min(100, (lane.p50LatencySec / 120) * 100);

  return (
    <article className="border border-grid bg-asphalt-50 p-4 hover:border-neon-cyan/30 transition-colors">
      <div className="flex items-start justify-between gap-2">
        <div>
          <p className="font-mono text-[10px] text-white/40 uppercase tracking-widest">
            {lane.id}
          </p>
          <h3 className="font-display text-sm tracking-wide mt-1">
            {lane.source.split(" ")[0]} → {lane.destination.split(" ")[0]}
          </h3>
        </div>
        <span
          className={`font-mono text-[10px] uppercase tracking-wider ${healthColor(lane.health)}`}
        >
          {lane.health}
        </span>
      </div>

      <div className="mt-4 space-y-2">
        <MetricRow label="p50" value={`${lane.p50LatencySec}s`} />
        <MetricRow label="p95" value={`${lane.p95LatencySec}s`} />
        <MetricRow
          label="Fee"
          value={lane.feeUsd > 0 ? `$${lane.feeUsd.toFixed(2)}` : "—"}
        />
        <MetricRow label="Success" value={`${lane.successRate}%`} />
      </div>

      <div className="mt-3 h-1.5 bg-asphalt overflow-hidden">
        <div
          className="h-full bg-gradient-to-r from-neon-cyan to-neon-amber transition-all"
          style={{ width: `${barWidth}%` }}
        />
      </div>
    </article>
  );
}

function MetricRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex justify-between font-mono text-xs">
      <span className="text-white/40">{label}</span>
      <span className="text-white/80">{value}</span>
    </div>
  );
}

function HeatmapTable({ lanes }: { lanes: LaneBenchmark[] }) {
  return (
    <div className="border border-grid overflow-x-auto">
      <table className="w-full min-w-[720px]">
        <thead>
          <tr className="border-b border-grid bg-asphalt-50 font-mono text-[10px] uppercase tracking-widest text-white/40">
            <th className="px-4 py-3 text-left">Route</th>
            <th className="px-4 py-3 text-left">Selectors</th>
            <th className="px-4 py-3 text-right">p50</th>
            <th className="px-4 py-3 text-right">p95</th>
            <th className="px-4 py-3 text-right">Health</th>
            <th className="px-4 py-3 text-right">Explorer</th>
          </tr>
        </thead>
        <tbody>
          {lanes.map((lane) => (
            <tr
              key={lane.id}
              className="border-b border-grid/60 hover:bg-asphalt-50/30"
            >
              <td className="px-4 py-3 font-mono text-xs">
                {lane.source} → {lane.destination}
              </td>
              <td className="px-4 py-3 font-mono text-[10px] text-white/40">
                {lane.sourceSelector.slice(0, 6)}… →{" "}
                {lane.destSelector.slice(0, 6)}…
              </td>
              <td className="px-4 py-3 text-right font-mono text-sm text-neon-cyan">
                {lane.p50LatencySec}s
              </td>
              <td className="px-4 py-3 text-right font-mono text-sm text-neon-amber">
                {lane.p95LatencySec}s
              </td>
              <td
                className={`px-4 py-3 text-right font-mono text-xs uppercase ${healthColor(lane.health)}`}
              >
                {lane.health}
              </td>
              <td className="px-4 py-3 text-right">
                <a
                  href={ccipExplorerHome()}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="font-mono text-[10px] text-neon-cyan/60 hover:text-neon-cyan"
                >
                  View →
                </a>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
