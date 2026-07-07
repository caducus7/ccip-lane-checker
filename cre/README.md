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

The `lane-benchmark` workflow writes a `BenchmarkSnapshot` JSON blob after each CRON or HTTP run and **POSTs it to `frontendCacheUrl`** from `config.staging.json` (default `http://localhost:3000/api/lanes`). Optional `frontendCacheAuthToken` is sent as `Authorization: Bearer …` when set.

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
2. Simulate `lane-benchmark` (CRON or HTTP trigger above). The workflow POSTs the snapshot to `frontendCacheUrl` automatically.
3. Open `/lanes` — the dashboard fetches `GET /api/lanes` and maps `totalMs` into p50/p95 display rows; if the cache is empty it falls back to `LANE_BENCHMARKS` in `frontend/src/lib/lane-data.ts`.

Manual POST (optional, e.g. without CRE):

```bash
curl -X POST http://localhost:3000/api/lanes \
  -H "Content-Type: application/json" \
  -d @snapshot.json
```

With auth enabled (`LANE_BENCHMARK_AUTH_TOKEN` in frontend `.env` and `frontendCacheAuthToken` in CRE config):

```bash
curl -X POST http://localhost:3000/api/lanes \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $LANE_BENCHMARK_AUTH_TOKEN" \
  -d @snapshot.json
```

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

Each workflow ships a pre-filled `config.staging.json` with placeholder contract addresses (`0x0000000000000000000000000000000000000001`) and chain metadata aligned to [`contracts/deployments/testnet.json`](../contracts/deployments/testnet.json). JSON cannot hold comments — field meanings and post-deploy steps are documented below.

### Staging config fill guide

**After `DeployAll.s.sol` on each chain**, copy deployed addresses from `testnet.json` → `contracts.*` into the workflow configs below. Until then, placeholders are valid for `cre workflow simulate` (read-only / dry-run).

| `testnet.json` chain key | CRE `chainSelectorName` | CCIP selector |
|--------------------------|-------------------------|---------------|
| `ethereum-sepolia` | `ethereum-testnet-sepolia` | `16015286601757825753` |
| `arbitrum-sepolia` | `ethereum-testnet-sepolia-arbitrum-1` | `3478487238524512106` |
| `base-sepolia` | `ethereum-testnet-sepolia-base-1` | `10344971235874465080` |

#### `round-scheduler` (`cre/lane-checker-cre/round-scheduler/config.staging.json`)

| Field | Staging value | Fill post-deploy |
|-------|---------------|------------------|
| `laneControllerAddress` | `0x00…01` | `testnet.json` → `chains.ethereum-sepolia.contracts.LaneController` |
| `chainSelectorName` | `ethereum-testnet-sepolia` | Fixed (controller home chain) |
| `lanePaths` | CCIP selectors for 3-chain race paths | Usually unchanged; matches deployed lane topology |
| `schedule`, `gasLimit` | CRON + gas | Tune for staging load |

#### `hop-sender` (`cre/lane-checker-cre/hop-sender/config.staging.json`)

Deploy **one workflow instance per chain** (separate CRE deployment). Staging file targets the **origin** (Ethereum Sepolia).

| Field | Staging value | Fill post-deploy |
|-------|---------------|------------------|
| `laneControllerAddress` | `0x00…01` | Sepolia `LaneController` |
| `laneExecutorAddress` | `0x00…01` | **This chain's** `LaneExecutor` |
| `controllerChainSelectorName` | `ethereum-testnet-sepolia` | Fixed for Sepolia-origin instance |
| `executorChainSelectorName` | `ethereum-testnet-sepolia` | CRE name for the chain this instance runs on |
| `isOriginChain` | `true` on Sepolia; `false` on Arbitrum/Base | CRON sends initial hops only on origin |
| `laneCount` | `2` | Match `round-scheduler` `lanePaths.length` |

For Arbitrum Sepolia / Base Sepolia instances: set `executorChainSelectorName` to the matching CRE name, `isOriginChain` to `false`, and `laneExecutorAddress` to that chain's deployed executor.

#### `hop-monitor` (`cre/lane-checker-cre/hop-monitor/config.staging.json`)

| Field | Staging value | Fill post-deploy |
|-------|---------------|------------------|
| `laneControllerAddress` | `0x00…01` | Sepolia `LaneController` (canonical event source) |
| `controllerChainSelectorName` | `ethereum-testnet-sepolia` | Fixed |
| `chains[]` | All three testnet CRE chain names | One log trigger pair (`HopCompleted`, `LaneFinished`) per entry |
| `gasLimit` | `500000` | Tune if needed |

#### `settlement` (`cre/lane-checker-cre/settlement/config.staging.json`)

| Field | Staging value | Fill post-deploy |
|-------|---------------|------------------|
| `laneControllerAddress` | `0x00…01` | Sepolia `LaneController` |
| `chainSelectorName` | `ethereum-testnet-sepolia` | Fixed (`WinnerDeclared` on controller chain) |
| `gasLimit` | `800000` | Tune if `distributePrizes` needs more gas |

#### `sweep-unclaimed` (`cre/lane-checker-cre/sweep-unclaimed/config.staging.json`)

| Field | Staging value | Fill post-deploy |
|-------|---------------|------------------|
| `laneControllerAddress` | `0x00…01` | Sepolia `LaneController` |
| `chainSelectorName` | `ethereum-testnet-sepolia` | Fixed |
| `claimWindowSeconds` | `86400` (1 day staging) | Match on-chain claim window |
| `lookbackMaxRounds` | `32` | Max rounds scanned per CRON tick |
| `schedule` | `0 0 */6 * * *` | Tune sweep frequency |

#### `lane-benchmark` (`cre/lane-checker-cre/lane-benchmark/config.staging.json`)

No on-chain addresses. Lanes use selectors from `testnet.json`; labels use chain keys (`ethereum-sepolia-to-arbitrum-sepolia`, etc.).

| Field | Staging value | Fill post-deploy |
|-------|---------------|------------------|
| `ccipApiBaseUrl` | `https://api.ccip.chain.link/v2` | Production URL if API host changes |
| `lanes[]` | All 6 directed testnet pairs | Add/remove pairs as CCIP lanes go live |
| `frontendCacheUrl` | `http://localhost:3000/api/lanes` | Staging/prod frontend `POST /api/lanes` URL |
| `frontendCacheAuthToken` | `""` (empty) | Set to match frontend `LANE_BENCHMARK_AUTH_TOKEN`; sent as `Authorization: Bearer …` |
| `authorizedKeys` | `[]` | HTTP trigger signing keys for manual refresh |
| `cacheKey` | `lane-benchmark-cache` | Must match frontend cache key expectations |

The workflow **automatically POSTs** each `BenchmarkSnapshot` to `frontendCacheUrl` after CRON and HTTP runs. POST failures are logged but do not fail the workflow (local dev can run without the Next.js server).

CCIP chain selectors (testnet lanes in configs):

| Network | CCIP Selector |
|---------|---------------|
| Ethereum Sepolia | `16015286601757825753` |
| Arbitrum Sepolia | `3478487238524512106` |
| Base Sepolia | `10344971235874465080` |

## Contract alignment

See [docs/CONSOLIDATION.md](../docs/CONSOLIDATION.md). After ABI changes run `scripts/sync-cre-abis.sh`.

LaneController must implement `IReceiver` (`onReport`). Canonical ABI: `shared/lane-controller-abi.ts`.

## Secrets

`secrets.yaml` uses references only. No API keys required for public CCIP lane latency endpoint.
