# CCIP Lane Checker — CRE Workflows

Chainlink CRE orchestration for parimutuel rounds (Step 3) and CCIP lane benchmarking (Step 6).

Project root: `cre/lane-checker-cre/` (contains `project.yaml`).

## Workflows

| Workflow | Trigger | Action |
|----------|---------|--------|
| `round-scheduler` | CRON `0 */30 * * * *` | `createRound` + `startRace` on LaneController |
| `hop-sender` | CRON `0 * * * * * *` + EVM Log (`HopReceived`) | `sendHop` on LaneExecutor (initial + continuation hops) |
| `hop-monitor` | EVM Log (`HopCompleted`, `LaneFinished`) | Track hops; winner declared on-chain by `recordHop` |
| `lane-benchmark` | CRON `0 */5 * * * *` + HTTP | Poll CCIP API lane latency; JSON cache output |
| `settlement` | EVM Log (`WinnerDeclared`) | `distributePrizes` + `sweepUnclaimed` on LaneController |

## Prerequisites

- CRE CLI: `/home/caducus/.cre/bin/cre` (or `cre` on PATH)
- Bun 1.2.21+
- `.env` with `CRE_ETH_PRIVATE_KEY` placeholder (simulation only; no real keys in repo)

## Install dependencies

From each workflow directory:

```bash
cd cre/lane-checker-cre/round-scheduler && bun install
cd ../hop-monitor && bun install
cd ../lane-benchmark && bun install
cd ../settlement && bun install
cd ../hop-sender && bun install
```

Typecheck all workflows locally (same as CI):

```bash
for wf in round-scheduler hop-sender hop-monitor settlement lane-benchmark; do
  (cd cre/lane-checker-cre/$wf && bun run typecheck)
done
```

## Simulate (compile check)

Run from **project root** (`cre/lane-checker-cre/`), always pass `--target`:

### CI / headless validation

`cre workflow simulate` requires an authenticated CRE CLI session (`cre login`), so CI uses a dry-run script instead:

```bash
./scripts/cre-simulate-check.sh
```

Locally, after `cre login`, you can also enable compile simulation:

```bash
CRE_SIMULATE=1 ./scripts/cre-simulate-check.sh
```

### round-scheduler (CRON only)

```bash
cd cre/lane-checker-cre
cre workflow simulate round-scheduler --target staging-settings
```

### lane-benchmark (CRON — fetches live CCIP API)

```bash
cre workflow simulate lane-benchmark --target staging-settings
```

### lane-benchmark (HTTP manual refresh)

Terminal 1:

```bash
cre workflow simulate lane-benchmark --target staging-settings
```

Terminal 2:

```bash
curl -X POST http://localhost:8080/trigger \
  -H "Content-Type: application/json" \
  -d '{"refresh": true}'
```

### lane-benchmark → frontend off-chain cache (staging)

The `lane-benchmark` workflow writes a `BenchmarkSnapshot` JSON blob after each CRON or HTTP run. In staging, POST that snapshot to the Next.js cache API so `/lanes` can serve live CCIP latency instead of static mock data.

**Frontend API** (`frontend/src/app/api/lanes/route.ts`):

| Method | Purpose |
|--------|---------|
| `GET` | Dashboard reads cached snapshot (`{ snapshot, source }`) |
| `POST` | CRE (or curl) upserts snapshot; optional auth when `LANE_BENCHMARK_AUTH_TOKEN` is set |

**Snapshot shape** (matches `lane-benchmark/main.ts`):

```json
{
  "cacheKey": "lane-benchmark-cache",
  "fetchedAt": "2026-07-07T12:00:00.000Z",
  "lanes": [
    {
      "label": "sepolia-to-arbitrum-sepolia",
      "sourceChainSelector": "16015286601757825753",
      "destChainSelector": "3478487238524512106",
      "totalMs": 42000,
      "sourceName": "Ethereum Sepolia",
      "destName": "Arbitrum Sepolia",
      "fetchedAt": "2026-07-07T12:00:00.000Z"
    }
  ]
}
```

**Local dev flow**

1. Start the frontend: `cd frontend && npm run dev` (default `http://localhost:3000`).
2. Simulate `lane-benchmark` (CRON or HTTP trigger above) and capture the JSON log output.
3. POST the snapshot to the cache:

```bash
curl -X POST http://localhost:3000/api/lanes \
  -H "Content-Type: application/json" \
  -d @snapshot.json
```

With auth enabled (`LANE_BENCHMARK_AUTH_TOKEN` in `.env`):

```bash
curl -X POST http://localhost:3000/api/lanes \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $LANE_BENCHMARK_AUTH_TOKEN" \
  -d @snapshot.json
```

4. Open `/lanes` — the dashboard fetches `GET /api/lanes` and maps `totalMs` into p50/p95 display rows; if the cache is empty it falls back to `LANE_BENCHMARKS` in `frontend/src/lib/lane-data.ts`.

**Storage:** in-memory singleton plus optional file persistence at `frontend/.cache/lane-benchmark.json` (survives dev server restarts when writable).

**Deployed staging:** point CRE HTTP action or a small relay at `https://<your-host>/api/lanes` with the same POST body and auth header.

### hop-sender (CRON — initial hops on origin chain)

```bash
cre workflow simulate hop-sender --target staging-settings
```

### hop-sender (EVM log — continuation after HopReceived)

```bash
cre workflow simulate hop-sender \
  --target staging-settings \
  --non-interactive \
  --trigger-index 1 \
  --evm-tx-hash 0x<TX_WITH_HOP_RECEIVED> \
  --evm-event-index 0
```

### hop-monitor (EVM log — needs tx with event)

```bash
cre workflow simulate hop-monitor \
  --target staging-settings \
  --non-interactive \
  --trigger-index 0 \
  --evm-tx-hash 0x<TX_WITH_HOP_COMPLETED> \
  --evm-event-index 0
```

Handler indices (staging): even = `HopCompleted`, odd = `LaneFinished` per chain (0–5 for 3 chains).

### settlement (EVM log — needs WinnerDeclared tx)

```bash
cre workflow simulate settlement \
  --target staging-settings \
  --non-interactive \
  --trigger-index 0 \
  --evm-tx-hash 0x<TX_WITH_WINNER_DECLARED> \
  --evm-event-index 0
```

### sweep-unclaimed (CRON — settled rounds past claim window)

```bash
cre workflow simulate sweep-unclaimed --target staging-settings
```

### On-chain writes (optional, after contracts deployed)

```bash
cre workflow simulate round-scheduler \
  --target staging-settings \
  --broadcast
```

Update `config.staging.json` addresses before broadcasting.

## Configuration

Replace placeholder `laneControllerAddress` (`0x00…01`) in each workflow's `config.staging.json` after testnet deployment.

CCIP chain selectors (testnet lanes in configs):

| Network | CCIP Selector |
|---------|---------------|
| Ethereum Sepolia | `16015286601757825753` |
| Arbitrum Sepolia | `3478487238524512106` |
| Base Sepolia | `10344971235874465078` |

## Contract alignment

See [docs/CONSOLIDATION.md](../docs/CONSOLIDATION.md). After ABI changes run `scripts/sync-cre-abis.sh`.

LaneController must implement `IReceiver` (`onReport`). Canonical ABI: `shared/lane-controller-abi.ts`.

## Secrets

`secrets.yaml` uses references only. No API keys required for public CCIP lane latency endpoint.
