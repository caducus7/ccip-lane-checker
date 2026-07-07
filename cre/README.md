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
| `settlement` | EVM Log (`WinnerDeclared`) | `distributePrizes` on LaneController |

`sweepUnclaimed` is **not** called here — it runs only after the claim window (manual or a delayed CRON) so bettors can `claimPrize` first.

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

## Simulate (compile check)

Run from **project root** (`cre/lane-checker-cre/`), always pass `--target`:

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
