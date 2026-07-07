/**
 * Shared benchmark cache types — aligned with
 * `cre/lane-checker-cre/lane-benchmark/main.ts` BenchmarkSnapshot shape.
 */

export type LaneBenchmarkEntry = {
  label: string;
  sourceChainSelector: string;
  destChainSelector: string;
  totalMs?: number;
  sourceName?: string;
  destName?: string;
  fetchedAt: string;
  error?: string;
};

export type BenchmarkSnapshot = {
  cacheKey: string;
  fetchedAt: string;
  lanes: LaneBenchmarkEntry[];
};

/** Optional fields present when lane-benchmark HTTP trigger runs. */
export type BenchmarkSnapshotHttp = BenchmarkSnapshot & {
  trigger?: "http";
  requestBody?: string;
};

export function isBenchmarkSnapshot(value: unknown): value is BenchmarkSnapshot {
  if (!value || typeof value !== "object") return false;
  const snap = value as BenchmarkSnapshot;
  return (
    typeof snap.cacheKey === "string" &&
    typeof snap.fetchedAt === "string" &&
    Array.isArray(snap.lanes)
  );
}
