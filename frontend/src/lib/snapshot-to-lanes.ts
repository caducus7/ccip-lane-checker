import type { BenchmarkSnapshot } from "@/lib/benchmark-types";
import type { LaneBenchmark } from "@/lib/lane-data";

function slugFromLabel(label: string): string {
  return label.replace(/-to-/g, "-").replace(/^sepolia/, "sep");
}

function healthFromEntry(
  totalMs: number | undefined,
  error: string | undefined,
): LaneBenchmark["health"] {
  if (error) return "down";
  if (totalMs === undefined) return "degraded";
  const sec = totalMs / 1000;
  if (sec < 40) return "excellent";
  if (sec < 60) return "good";
  if (sec < 120) return "degraded";
  return "degraded";
}

function displayName(name: string | undefined, selector: string): string {
  if (name) return name;
  return `Chain ${selector.slice(0, 6)}…`;
}

/**
 * Maps a CRE BenchmarkSnapshot into dashboard LaneBenchmark rows.
 * CCIP lane-latency returns a single percentile (logged as p90 in CRE); p95 is estimated.
 */
export function snapshotToLaneBenchmarks(
  snapshot: BenchmarkSnapshot,
): LaneBenchmark[] {
  return snapshot.lanes.map((entry) => {
    const p50LatencySec =
      entry.totalMs !== undefined ? Math.round(entry.totalMs / 1000) : 0;
    const p95LatencySec =
      entry.totalMs !== undefined
        ? Math.round((entry.totalMs * 1.5) / 1000)
        : 0;

    return {
      id: slugFromLabel(entry.label),
      source: displayName(entry.sourceName, entry.sourceChainSelector),
      destination: displayName(entry.destName, entry.destChainSelector),
      sourceSelector: entry.sourceChainSelector,
      destSelector: entry.destChainSelector,
      p50LatencySec,
      p95LatencySec,
      feeUsd: 0,
      successRate: entry.error ? 0 : 99,
      health: healthFromEntry(entry.totalMs, entry.error),
      lastUpdated: entry.fetchedAt || snapshot.fetchedAt,
    };
  });
}
