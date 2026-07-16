import { NextResponse } from "next/server";

import { isBenchmarkSnapshot } from "@/lib/benchmark-types";
import {
  getBenchmarkSnapshot,
  setBenchmarkSnapshot,
} from "@/lib/lane-benchmark-cache";

function isAuthorized(request: Request): boolean {
  const expected = process.env.LANE_BENCHMARK_AUTH_TOKEN;
  if (!expected || expected.trim() === "") {
    return false;
  }

  const authHeader = request.headers.get("authorization");
  if (authHeader === `Bearer ${expected}`) return true;

  const benchmarkAuth = request.headers.get("x-benchmark-auth");
  return benchmarkAuth === expected;
}

export async function GET() {
  const snapshot = await getBenchmarkSnapshot();

  if (!snapshot) {
    return NextResponse.json(
      { snapshot: null, source: "empty" as const },
      { status: 200 },
    );
  }

  return NextResponse.json(
    { snapshot, source: "cache" as const },
    {
      status: 200,
      headers: { "Cache-Control": "no-store" },
    },
  );
}

export async function POST(request: Request) {
  if (!process.env.LANE_BENCHMARK_AUTH_TOKEN?.trim()) {
    return NextResponse.json(
      { error: "LANE_BENCHMARK_AUTH_TOKEN is not configured" },
      { status: 503 },
    );
  }

  if (!isAuthorized(request)) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  if (!isBenchmarkSnapshot(body)) {
    return NextResponse.json(
      {
        error:
          "Body must match BenchmarkSnapshot: { cacheKey, fetchedAt, lanes[] }",
      },
      { status: 400 },
    );
  }

  const stored = await setBenchmarkSnapshot(body);

  return NextResponse.json(
    { ok: true, snapshot: stored },
    { status: 200 },
  );
}
