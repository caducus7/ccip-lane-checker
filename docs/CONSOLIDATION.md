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

Run `./scripts/sync-cre-abis.sh` after contract ABI changes.

## Settlement flow (all stacks)

```
round-scheduler (CRE)  → createRound + startRace
hop-sender (CRE/ops)   → LaneExecutor.sendHop per leg
LaneExecutor           → recordHop on controller
hop-monitor (CRE)      → declareWinner fallback on LaneFinished
settlement (CRE)       → distributePrizes
Frontend               → claimPrize (pull payout)
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

**33/33** `forge test` passing (unit + Chainlink Local integration). Path-aware `_finishLane` in `LaneController.t.sol` aligns with executor 4-tuple encoding.

## Post-deploy checklist

See **`docs/DEPLOY_TESTNET.md`** for phased `DeployAll.s.sol` commands (deploy → peer wiring).

- [ ] Fill `contracts/deployments/testnet.json` per chain
- [ ] Update each CRE workflow `config.staging.json` with controller + executor addresses
- [ ] Set `creForwarder` on LaneController **and** each LaneExecutor to network KeystoneForwarder
- [ ] `setHopSender(creForwarder)` on each LaneExecutor (optional if using `onReport` only)
- [ ] `setHopRecorder(executor)` on LaneController per chain
- [ ] `setRemoteExecutor` on each executor for peer chains
- [ ] Fund executors with native token for CCIP fees
