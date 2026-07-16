# CCIP Lane Checker — Implementation Steps

Start-to-finished-product plan. Each step is independently shippable.

---

## Research Decisions (locked in)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Randomness for hop selection | **On-chain VRF v2.5** | Cryptographically verifiable; players can audit outcomes. CRE `runtime.Rand()` is DON-internal and not suitable for trustless betting. |
| Winner determination | **On-chain timestamps** | First lane to complete circuit wins — no randomness needed. CRE observes `HopCompleted` / `LaneFinished` events. |
| Orchestration | **CRE** | Replaces deprecated Automation (scheduling) and Functions (off-chain logic). |
| Lane metrics | **CCIP API / SDK** | Real lane latency, fees, message status for benchmarking layer. |
| CCIP version | **Current v1.6.x** | vNext not public; abstract via `IRouterClient` + config-driven selectors. |
| Betting | **Both modes** | Solo challenge + parimutuel pool share CCIP/VRF infra, different entry contracts. |

---

## Step 0 — Bootstrap ✅

- [x] New monorepo at `ccip-lane-checker`
- [x] Foundry scaffold + deps (no full chainlink monorepo submodule)
- [x] CRE project scaffold (`lane-checker-cre`)
- [x] Migrate `LaneToken` + fix `HopCompleted` emission
- [x] Passing unit tests
- [ ] Push to `github.com/caducus7/ccip-lane-checker` (run locally: `gh repo create caducus7/ccip-lane-checker --public --source=. --remote=origin`)

---

## Step 1 — Contract Foundation ✅

**Goal:** Clean, tested on-chain core with CCIP vNext-ready boundaries.

1. [x] Add `interfaces/ICcipRouter.sol` wrapper around `IRouterClient` (swap point for vNext)
2. [x] Add `libraries/ChainConfig.sol` — testnet selectors (Sepolia, Arbitrum Sepolia, Base Sepolia)
3. [x] Add `libraries/PrizeCalculator.sol` — 70/15/10/5 split
4. [x] Migrate `LaneToken` VRF v2 → **VRF v2.5** (`VRFConsumerBaseV2Plus`, `uint256` sub ID)
5. [x] Add Chainlink Local integration test (`test/integration/CCIPLocal.t.sol`)
6. [x] Deploy scripts: `script/DeploySimulator.s.sol`, `script/DeployLaneToken.s.sol`, `script/DeployAll.s.sol`

**Exit criteria:** `forge test` green; local CCIP simulator round-trip works. **Met.**

---

## Step 2 — Parimutuel Mode (`LaneController`) ✅

**Goal:** Multi-lane betting pool.

1. [x] Implement `LaneController.sol`:
   - `createRound(lanePaths)` — admin/CRE creates round with N predefined chain circuits
   - `buyLaneTokens(roundId, laneId, amount)` — parimutuel entry
   - `startRace(roundId)` — locks betting, triggers lane token sends
   - `recordHop(roundId, laneId, latency)` — called by per-chain `LaneExecutor`
   - `declareWinner(roundId, laneId)` — CRE-gated or first-complete-wins
   - `distributePrizes(roundId)` — via `PrizeCalculator`
2. [x] Implement `LaneExecutor.sol` per chain — `CCIPReceiver`, forwards hop data to controller
3. [x] Fuzz tests on prize math and round state machine (`LaneController.t.sol`, `PrizeCalculator.t.sol`)
4. [x] Multi-fork Chainlink Local test: 2 lanes, 3 chains (`test/integration/ParimutuelRace.t.sol`)

**Exit criteria:** Full parimutuel round simulates locally end-to-end. **Met.**

---

## Step 3 — CRE Orchestration 🟡

**Goal:** Replace Automation/Functions with CRE workflows.

### Workflow A: `round-scheduler` (CRON)
- [x] Trigger: `0 */30 * * * *` (every 30 min on testnet)
- [x] Action: EVM write `LaneController.createRound()` + `startRace()` after betting window

### Workflow B: `hop-monitor` (EVM Log)
- [x] Trigger: `HopCompleted`, `LaneFinished` events on all deployed chains
- [x] Action: Track hops; winner declared on-chain by `recordHop` (no CRE `declareWinner` fallback)

### Workflow C: `lane-benchmark` (CRON + HTTP)
- [x] Trigger: every 5 min
- [x] Read: CCIP API lane latency for configured selectors
- [x] Write: cache to HTTP endpoint / on-chain registry for frontend

### Workflow D: `settlement` (EVM Log)
- [x] Trigger: `WinnerDeclared` event
- [x] Action: EVM write `distributePrizes()` + `sweepUnclaimed()`

### Workflow E: `hop-sender` (CRON + EVM Log)
- [x] Trigger: CRON initial hops + `HopReceived` continuation
- [x] Action: `LaneExecutor.sendHop` per race leg

### Workflow F: `sweep-unclaimed` (CRON)
- [x] Trigger: every 6 h (staging) / daily (production config)
- [x] Action: `sweepUnclaimed(roundId)` for settled rounds past `claimWindowSeconds`

**Setup:**
```bash
cd cre/lane-checker-cre
cre login                    # browser auth
cre workflow simulate round-scheduler --target staging-settings
# add --rpc-url flags per chain
```

**Exit criteria:** Simulated CRE round creates, monitors, and settles a race on testnet.
- [x] Local simulation (`cre workflow simulate`) compiles and runs
- [ ] Live testnet DON deployment + E2E round with real CCIP hops

---

## Step 4 — Testnet Deployment 🟡

**Goal:** Live demo on 2–3 testnets.

**Chains:** Ethereum Sepolia, Arbitrum Sepolia, Base Sepolia (CCIP-connected lanes)

1. [x] Deploy script: `script/DeployAll.s.sol` (LaneToken + LaneController + LaneExecutor + wiring)
2. [x] `ChainConfig.creForwarder` per network (KeystoneForwarder addresses)
3. [x] Deployment manifest: `contracts/deployments/testnet.json` (+ schema)
4. [x] Step-by-step checklist: `docs/DEPLOY_TESTNET.md`
5. [x] Register VRF v2.5 subscription per chain; fund with LINK
6. [x] Allowlist CCIP lanes between deployed chains (CCIP Directory)
7. [x] Deploy contracts on testnet (3 chains)
8. [x] Cross-chain peer wiring (`remoteExecutors`, `remoteLaneTokens`, `hopRecorder`)
9. [ ] Deploy CRE workflows to testnet DON
10. [ ] Smoke test: solo challenge + one parimutuel round
11. [x] Fill live addresses in `contracts/deployments/testnet.json`

**Exit criteria:** Manual E2E race completes on testnet with CRE settlement. **Not yet met** — operator UI + `scripts/manual-parimutuel-smoke.sh` available as CRE substitute.

---

## Step 5 — Frontend (Testnet Demo) 🟡

**Goal:** Playable UI for both game modes.

**Stack:** Next.js 15, wagmi/viem, Tailwind

### Pages
| Route | Purpose | Status |
|-------|---------|--------|
| `/` | Landing — active rounds, lane health | [x] Scaffolded |
| `/solo` | Start solo challenge, watch hops live | [x] Scaffolded |
| `/race/:roundId` | Parimutuel — bet on lanes, live race viz | [x] Scaffolded |
| `/leaderboard` | Solo + race history, latency stats | [x] Scaffolded |
| `/lanes` | CCIP lane benchmark dashboard (API-fed) | [x] Scaffolded |

### Features
- [x] Wallet connect (Sepolia + Arbitrum Sepolia + Base Sepolia)
- [x] Live hop progress via on-chain `getLane()` polling (3s) + CCIP Explorer links
- [x] Animated lane race visualization
- [x] Bet placement + prize pool display + `claimPrize` flow
- [x] Tx feedback (pending / success / error) + LINK `approve` UX on solo + parimutuel
- [x] CCIP Explorer deep links (`buildCcipExplorerMessageUrl` in `HopProgress`)
- [x] `/lanes` dashboard reads `GET /api/lanes` with static fallback
- [x] Owner **Race Control** panel (create / start / send hops / settle) for testnet without CRE DON

**Exit criteria:** Full solo + parimutuel playable from browser on testnet. **Ready for operator smoke** (CRE DON optional).

---

## Step 6 — Benchmarking Layer 🟡

**Goal:** Real CCIP lane performance data, not just game latency.

1. [x] CRE `lane-benchmark` workflow polls CCIP API `lane-latency` per route
2. [x] Off-chain cache via `POST /api/lanes` (in-memory + `frontend/.cache/lane-benchmark.json`)
3. [x] Frontend `/lanes` dashboard (cache → static `LANE_BENCHMARKS` fallback)
4. [ ] Use benchmark data to weight lane difficulty in race scoring (optional handicap)
5. [ ] On-chain `LaneRegistry` (deferred — off-chain cache sufficient for demo)

**Exit criteria:** Dashboard shows live CCIP lane metrics alongside game results. **Met for staging** (CRE POST → cache → UI).

---

## Step 7 — Production Hardening

1. [ ] Security review (`solidity-auditor` skill on full `contracts/src`)
2. [x] Access control audit on CRE write paths (`CreReportAuth` selector allowlist; `creForwarder` gating)
3. [x] Gas optimization pass (`Round` slot packing; `uint48` rate-limit fields; inline `requiredHops`; flat `sendHop` gas via external hop sends)
4. [x] Rate limiting on round creation (`roundCooldown`, default 60 s; owner-tunable; applies to CRE `onReport` too)
5. [x] Emergency pause on `LaneController` (`LaneControllerPausable`)
6. [x] Comprehensive integration test suite (Chainlink Local multi-fork + `FullSmoke.t.sol` solo/parimutuel lifecycles)
7. [x] CI: `forge test` + CRE typecheck/unit tests + `cre-validate` (`scripts/cre-simulate-check.sh` ABI sync on PR)

---

## Step 8 — Mainnet Path

1. [ ] CCIP vNext migration assessment (when public)
2. [ ] Mainnet lane selection (high-liquidity routes only)
3. [ ] Audit (external or contest)
4. [ ] Gradual rollout: solo mode first → parimutuel with capped pools
5. [ ] CRE workflows on mainnet DON
6. [ ] Monitoring: CCIP Explorer + custom alerts for stuck messages

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                      Frontend (Next.js)                  │
│  Solo Challenge │ Parimutuel Race │ Lane Benchmarks     │
└────────┬────────────────┬─────────────────┬──────────────┘
         │                │                 │
    ┌────▼────┐     ┌─────▼─────┐    ┌─────▼─────┐
    │LaneToken│     │LaneController│   │ CCIP API  │
    │ (solo)  │     │ (parimutuel)│   │ (metrics) │
    └────┬────┘     └─────┬─────┘    └───────────┘
         │                │
    ┌────▼────────────────▼────┐
    │     LaneExecutor (×N)     │  ← one per chain
    │     CCIPReceiver          │
    └────────────┬───────────────┘
                 │ CCIP hops
    ┌────────────▼───────────────┐
    │   CRE Workflows            │
    │   CRON: schedule rounds    │
    │   EVM Log: hop monitor     │
    │   EVM Write: settle        │
    │   HTTP: benchmark cache    │
    └────────────────────────────┘
```

## CCIP vNext Migration Notes

When vNext is public:
1. Swap `ICcipRouter` implementation
2. Update `Client.EVM2AnyMessage` extraArgs if schema changes
3. Re-run Chainlink Local tests with new simulator
4. No game logic changes expected — only transport layer

---

## Cursor Session Prompts (copy-paste per step)

**Step 1:** "Implement Step 1 from docs/IMPLEMENTATION.md — VRF v2.5 migration, ChainConfig, PrizeCalculator, CCIP Local integration test"

**Step 2:** "Implement Step 2 — full LaneController parimutuel mode with LaneExecutor and fuzz tests"

**Step 3:** "Implement Step 3 — CRE workflows round-scheduler, hop-monitor, settlement"

**Step 4:** "Follow docs/DEPLOY_TESTNET.md — deploy contracts on Sepolia, Arbitrum Sepolia, Base Sepolia"

**Step 5:** "Implement Step 5 — Next.js frontend with solo + parimutuel pages on testnet"
