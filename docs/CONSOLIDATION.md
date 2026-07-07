# Cross-Stack Consolidation

Parallel agents built contracts, CRE workflows, and frontend concurrently. This doc tracks alignment.

## Source of truth

| Concern | Canonical location |
|---------|-------------------|
| LaneController ABI (write/events) | `cre/lane-checker-cre/shared/lane-controller-abi.ts` |
| LaneController ABI (frontend reads) | `frontend/src/lib/contracts.ts` → `laneControllerAbi` |
| LaneExecutor ABI (hop sends) | `cre/lane-checker-cre/shared/lane-executor-abi.ts` |
| Deployed addresses | `contracts/deployments/testnet.json` |
| Chain selectors | `contracts/src/libraries/ChainConfig.sol` + `frontend/src/lib/chains.ts` |
| Env templates | `contracts/.env.example` (deploy) + `frontend/.env.example` (UI + `LANE_BENCHMARK_AUTH_TOKEN`) |

Run `./scripts/sync-cre-abis.sh` after contract ABI changes.

## Testnets (3-chain)

All stacks target **Ethereum Sepolia**, **Arbitrum Sepolia**, and **Base Sepolia**. Canonical selectors and CRE forwarders live in `ChainConfig.sol` and `contracts/deployments/testnet.json`. Base Sepolia uses the same Keystone forwarder address as Sepolia (`0xF834…4482`); Arbitrum Sepolia differs — verify before deploy.

## Settlement flow (all stacks)

```
round-scheduler (CRE)  → createRound + startRace
hop-sender (CRE/ops)   → LaneExecutor.sendHop per leg
LaneExecutor           → recordHop on controller
hop-monitor (CRE)      → declareWinner fallback on LaneFinished
settlement (CRE)       → distributePrizes
sweep-unclaimed (CRE)  → sweepUnclaimed (after claim window)
lane-benchmark (CRE)   → CCIP API poll → POST /api/lanes
Frontend               → claimPrize (pull payout); GET /api/lanes (dashboard)
```

## Known integration rules

1. **Betting token is ERC20**, not native ETH — frontend must `approve` before `buyLaneTokens` / `deposit`.
2. **`getRoundWinner` returns `255` (`NO_LANE`)** when unset — never compare `!== 0`.
3. **`recordHop` auto-declares** first finisher; CRE `declareWinner` is fallback only.
4. **CRE writes** go through `onReport` on LaneController and LaneExecutor (Keystone forwarder as `creForwarder`). Selectors are allowlisted via `CreReportAuth`; `whenNotPaused` applies on controller.
5. **Hop sends** via `LaneExecutor.sendHop` — CRE uses `writeReport` → `onReport` (allowlisted `sendHop` only) or direct `hopSender` calls.
6. **`recordHop` accepts `sendTime`** — latency is derived on-chain (`block.timestamp - sendTime`, capped at 30 days). `chainSelector` must match `lane.chainPath[hopsCompleted]`; `LaneExecutor` encodes the destination chain in the CCIP message as a 4-tuple `(roundId, laneId, hopChainSelector, sendTime)`.
7. **`sweepUnclaimed(roundId)`** — CRE/owner can recover unclaimed winner/runner-up shares after settlement. **Do not** call from `settlement` immediately after `distributePrizes` — bettors need time to `claimPrize` first; use a delayed CRON if automated.
8. **`round-orchestrator` removed** — hop sends are owned by `hop-sender`; settlement only calls `distributePrizes` on `WinnerDeclared`.

## lane-benchmark → `/api/lanes` cache

1. CRE `lane-benchmark` CRON (every 5 min) or HTTP trigger fetches `GET {ccipApiBaseUrl}/lanes/latency?sourceChainSelector=…&destChainSelector=…` per route in `config.staging.json`.
2. Workflow logs a `BenchmarkSnapshot` JSON blob (`cacheKey`, `fetchedAt`, `lanes[]` with `totalMs`).
3. Relay POSTs that snapshot to the frontend:

```bash
curl -X POST https://<host>/api/lanes \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $LANE_BENCHMARK_AUTH_TOKEN" \
  -d @snapshot.json
```

4. `GET /api/lanes` returns `{ snapshot, source }`; `/lanes` maps `totalMs` into display rows. Empty cache falls back to `LANE_BENCHMARKS` in `frontend/src/lib/lane-data.ts`.

Auth: optional `LANE_BENCHMARK_AUTH_TOKEN` (see `frontend/.env.example`). Storage: in-memory + `frontend/.cache/lane-benchmark.json`. Full curl examples in `cre/README.md`.

## Security hardening (applied)

| Finding | Fix |
|---------|-----|
| `onReport` arbitrary `self.call` | `CreReportAuth` selector allowlist |
| `onReport` bypasses pause | `whenNotPaused` on controller `onReport` |
| `recordHop` trusted latency param | On-chain derivation from `sendTime` |
| Claim rounding dust | `winnerShareClaimed` / `runnerUpShareClaimed` + `sweepUnclaimed` |
| Missing hop orchestration | `hop-sender` CRE workflow (CRON initial + `HopReceived` continuation) |
| `recordHop` wrong-chain hops | Path validation vs `lane.chainPath[hopsCompleted]`; executor passes `hopChainSelector` in message data |
| Premature prize sweep | `settlement` no longer calls `sweepUnclaimed` right after `distributePrizes` |

## Test status

**42/42** `forge test` passing locally (6 fork tests skipped without RPC). Includes `FullSmoke.t.sol` solo + parimutuel lifecycles. Path-aware `_finishLane` in `LaneController.t.sol` aligns with executor 4-tuple encoding.

## Post-deploy checklist

See **`docs/DEPLOY_TESTNET.md`** for phased `DeployAll.s.sol` commands (deploy → peer wiring).

- [ ] Fill `contracts/deployments/testnet.json` per chain
- [ ] Update each CRE workflow `config.staging.json` with controller + executor addresses
- [ ] Set `creForwarder` on LaneController **and** each LaneExecutor to network KeystoneForwarder
- [ ] `setHopSender(creForwarder)` on each LaneExecutor (optional if using `onReport` only)
- [ ] `setHopRecorder(executor)` on LaneController per chain
- [ ] `setRemoteExecutor` on each executor for peer chains
- [ ] Fund executors with native token for CCIP fees
