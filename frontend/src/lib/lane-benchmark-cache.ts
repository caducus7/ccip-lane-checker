import { mkdir, readFile, writeFile } from "fs/promises";
import path from "path";

import {
  type BenchmarkSnapshot,
  isBenchmarkSnapshot,
} from "@/lib/benchmark-types";

const CACHE_DIR = path.join(process.cwd(), ".cache");
const CACHE_FILE = path.join(CACHE_DIR, "lane-benchmark.json");

let memorySnapshot: BenchmarkSnapshot | null = null;

async function readFileSnapshot(): Promise<BenchmarkSnapshot | null> {
  try {
    const raw = await readFile(CACHE_FILE, "utf8");
    const parsed: unknown = JSON.parse(raw);
    return isBenchmarkSnapshot(parsed) ? parsed : null;
  } catch {
    return null;
  }
}

async function writeFileSnapshot(snapshot: BenchmarkSnapshot): Promise<void> {
  await mkdir(CACHE_DIR, { recursive: true });
  await writeFile(CACHE_FILE, JSON.stringify(snapshot, null, 2), "utf8");
}

export async function getBenchmarkSnapshot(): Promise<BenchmarkSnapshot | null> {
  if (memorySnapshot) return memorySnapshot;
  const fromFile = await readFileSnapshot();
  if (fromFile) memorySnapshot = fromFile;
  return fromFile;
}

export async function setBenchmarkSnapshot(
  snapshot: BenchmarkSnapshot,
): Promise<BenchmarkSnapshot> {
  memorySnapshot = snapshot;
  try {
    await writeFileSnapshot(snapshot);
  } catch {
    // File persistence is best-effort in dev; in-memory store still works.
  }
  return snapshot;
}
