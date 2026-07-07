# Pre-Deploy Runbook

Operational checklist before first testnet deploy. Pair with **`docs/DEPLOY_TESTNET.md`** for contract commands.

---

## 1. Executor native ETH funding

Each `LaneExecutor` pays CCIP fees in **native token** (`feeToken = address(0)` in `sendHop`). Fund via plain transfer to the executor address (`receive()` is open).

| Network | Initial top-up | Refill trigger | Notes |
|---------|----------------|----------------|-------|
| Ethereum Sepolia | **0.05 ETH** | Balance &lt; 0.01 ETH | Origin chain; most `hop-sender` CRON traffic |
| Arbitrum Sepolia | **0.02 ETH** | Balance &lt; 0.005 ETH | Lower L2 fees |
| Base Sepolia | **0.02 ETH** | Balance &lt; 0.005 ETH | Same forwarder as Sepolia |

**Sizing (per parimutuel round, 2 lanes × 3-hop circuit):** ~6 CCIP sends total. At current testnet rates, budget **~0.001–0.003 ETH per hop** on Sepolia (varies by gas price and message size). A 0.05 ETH buffer covers **~15–30 rounds** before refill.

```bash
# Check balance (repeat per chain)
cast balance $LANE_EXECUTOR --rpc-url $SEPOLIA_RPC
```

---

## 2. LINK + VRF v2.5 subscription

One subscription **per chain** where `LaneToken` is deployed (solo mode VRF callbacks).

| Step | Action |
|------|--------|
| Create sub | [vrf.chain.link](https://vrf.chain.link) → network → Create subscription |
| Record ID | Export as `VRF_SUBSCRIPTION_ID` in `contracts/.env` per `DEPLOY_CHAIN` |
| Add consumer | After deploy: add `LaneToken` address to the subscription |
| Fund LINK | **5–10 LINK** per chain to start (2–3 solo games + headroom) |
| Verify key | Deploy script sets `keyHash` / `gasLane` from `ChainConfig` — confirm they match the network coordinator |

**Post-deploy smoke:** `LaneToken.startGame` → VRF callback within ~1–3 blocks. If stuck: consumer not added, insufficient LINK, or wrong `VRF_SUBSCRIPTION_ID`.

---

## 3. CCIP fee ballpark

`LaneExecutor.sendHop` calls `router.getFee(destChainSelector, message)` then `ccipSend{value: fee}`.

| Route (testnet) | Typical fee (native) | Latency (p90) |
|-----------------|----------------------|---------------|
| Sepolia → Arbitrum Sepolia | ~0.0005–0.002 ETH | 30–90 s |
| Sepolia → Base Sepolia | ~0.0005–0.002 ETH | 30–90 s |
| Arbitrum ↔ Base (if wired) | ~0.0001–0.0005 ETH | 20–60 s |

Fees are **message-size and gas-price dependent**. No token transfers in hop messages (data-only), so fees stay at the low end. If `sendHop` reverts on fee: executor underfunded — top up native token.

Confirm lanes are allowlisted in [CCIP Directory](https://ccip.chain.link) for all three selectors before first send.

---

## 4. sweep-unclaimed timing

`sweep-unclaimed` CRE workflow recovers winner/runner-up dust after bettors had time to `claimPrize`.

| Config | Staging | Production |
|--------|---------|------------|
| CRON | `0 0 */6 * * *` (every 6 h) | Tighter in `config.production.json` |
| `claimWindowSeconds` | **86400** (24 h) | **604800** (7 d) |
| `lookbackMaxRounds` | 32 | 32 |

**Rule:** `settlement` calls `distributePrizes` only — **never** `sweepUnclaimed` in the same tx. Eligibility: `round.state == Settled` AND `now >= winnerFinishTime + claimWindowSeconds`.

Manual check:

```bash
cre workflow simulate sweep-unclaimed --target staging-settings
```

---

## 5. Monitoring

### Stuck CCIP messages

| Signal | Check | Action |
|--------|-------|--------|
| Hop sent, no `HopReceived` | [CCIP Explorer](https://ccip.chain.link) → message ID from `HopSent` event | Wait for lane latency; if &gt; 15 min, check RMN / lane status |
| `sendHop` reverts | Executor native balance | Top up ETH |
| `UnauthorizedSource` on receive | `remoteExecutors` mismatch | Re-run Phase 2 peer wiring (`docs/DEPLOY_TESTNET.md`) |
| Race stalled mid-round | `HopCompleted` count vs expected | `hop-sender` CRON + `HopReceived` log trigger |

Frontend: `HopProgress` links to CCIP Explorer via `buildCcipExplorerMessageUrl`.

### CRE workflow health

| Workflow | Healthy signal | Alert if |
|----------|----------------|----------|
| `round-scheduler` | `RoundCreated` + `RaceStarted` every ~30 min | No new round &gt; 2 h; `RoundCooldownActive` in logs |
| `hop-sender` | `HopSent` events per active round | Missing hops &gt; 10 min after `RaceStarted` |
| `hop-monitor` | `WinnerDeclared` or auto via `recordHop` | Round in `Racing` &gt; 1 h |
| `settlement` | `PrizesDistributed` after `WinnerDeclared` | Winner declared but no distribution &gt; 5 min |
| `sweep-unclaimed` | Periodic `UnclaimedSwept` (optional) | N/A unless treasury tracking |
| `lane-benchmark` | Fresh `fetchedAt` on `GET /api/lanes` | Snapshot &gt; 15 min stale |

**CI baseline:** `.github/workflows/ci.yml` runs `forge test`, frontend build, CRE typecheck, and `cre-validate` (ABI sync). Green CI ≠ live DON health — monitor on-chain events after DON deploy.

---

## Quick pre-flight

- [ ] `contracts/.env` + `frontend/.env` copied from `.env.example`
- [ ] VRF subs created + funded (3 chains)
- [ ] CCIP lanes enabled (Sepolia ↔ Arb Sepolia ↔ Base Sepolia)
- [ ] Executor funded with native token (table above)
- [ ] `testnet.json` addresses filled after deploy
- [ ] CRE `config.staging.json` updated per workflow
- [ ] `LANE_BENCHMARK_AUTH_TOKEN` set if `/api/lanes` POST is exposed
