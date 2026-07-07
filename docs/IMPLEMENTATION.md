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

## Step 0 — Bootstrap ✅ (this session)

- [x] New monorepo at `ccip-lane-checker`
- [x] Foundry scaffold + deps (no full chainlink monorepo submodule)
- [x] CRE project scaffold (`lane-checker-cre`)
- [x] Migrate `LaneToken` + fix `HopCompleted` emission
- [x] Passing unit tests
- [ ] Push to `github.com/caducus7/ccip-lane-checker` (run locally: `gh repo create caducus7/ccip-lane-checker --public --source=. --remote=origin`)

---

## Step 1 — Contract Foundation

**Goal:** Clean, tested on-chain core with CCIP vNext-ready boundaries.

1. Add `interfaces/ICcipRouter.sol` wrapper around `IRouterClient` (swap point for vNext)
2. Add `libraries/ChainConfig.sol` — testnet selectors (Sepolia, Arbitrum Sepolia, Base Sepolia)
3. Add `libraries/PrizeCalculator.sol` — 70/15/10/5 split
4. Migrate `LaneToken` VRF v2 → **VRF v2.5** (`VRFConsumerBaseV2Plus`, `uint256` sub ID)
5. Add Chainlink Local integration test (`test/integration/CCIPLocal.t.sol`)
6. Deploy scripts: `script/DeploySimulator.s.sol`, `script/DeployLaneToken.s.sol`

**Exit criteria:** `forge test` green; local CCIP simulator round-trip works.

---

## Step 2 — Parimutuel Mode (`LaneController`)

**Goal:** Multi-lane betting pool.

1. Implement `LaneController.sol`:
   - `createRound(lanePaths)` — admin/CRE creates round with N predefined chain circuits
   - `buyLaneTokens(roundId, laneId, amount)` — parimutuel entry
   - `startRace(roundId)` — locks betting, triggers lane token sends
   - `recordHop(roundId, laneId, latency)` — called by per-chain `LaneExecutor`
   - `declareWinner(roundId, laneId)` — CRE-gated or first-complete-wins
   - `distributePrizes(roundId)` — via `PrizeCalculator`
2. Implement `LaneExecutor.sol` per chain — `CCIPReceiver`, forwards hop data to controller
3. Fuzz tests on prize math and round state machine
4. Multi-fork Chainlink Local test: 2 lanes, 3 chains

**Exit criteria:** Full parimutuel round simulates locally end-to-end.

---

## Step 3 — CRE Orchestration

**Goal:** Replace Automation/Functions with CRE workflows.

### Workflow A: `round-scheduler` (CRON)
- Trigger: `0 */30 * * * *` (every 30 min on testnet)
- Action: EVM write `LaneController.createRound()` + `startRace()` after betting window

### Workflow B: `hop-monitor` (EVM Log)
- Trigger: `HopCompleted`, `LaneFinished` events on all deployed chains
- Action: Update round state; if first finisher → `declareWinner()`

### Workflow C: `lane-benchmark` (CRON + HTTP)
- Trigger: every 5 min
- Read: CCIP API lane latency for configured selectors
- Write: cache to HTTP endpoint / on-chain registry for frontend

### Workflow D: `settlement` (EVM Log)
- Trigger: `WinnerDeclared` event
- Action: EVM write `distributePrizes()` + `sweepUnclaimed()`

**Setup:**
```bash
cd cre/lane-checker-cre
cre login                    # browser auth
cre workflow simulate round-scheduler --target staging-settings
# add --rpc-url flags per chain
```

**Exit criteria:** Simulated CRE round creates, monitors, and settles a race on testnet.

---

## Step 4 — Testnet Deployment

**Goal:** Live demo on 2–3 testnets.

**Chains:** Ethereum Sepolia, Arbitrum Sepolia, Base Sepolia (CCIP-connected lanes)

1. Deploy `LaneToken` + `LaneController` + `LaneExecutor` per chain
2. Register VRF v2.5 subscription per chain; fund with LINK
3. Allowlist CCIP lanes between deployed chains
4. Deploy CRE workflows to testnet DON
5. Smoke test: solo challenge + one parimutuel round
6. Document addresses in `contracts/deployments/testnet.json`

**Exit criteria:** Manual E2E race completes on testnet with CRE settlement.

---

## Step 5 — Frontend (Testnet Demo)

**Goal:** Playable UI for both game modes.

**Stack:** Next.js 15, wagmi/viem, Tailwind

### Pages
| Route | Purpose |
|-------|---------|
| `/` | Landing — active rounds, lane health |
| `/solo` | Start solo challenge, watch hops live |
| `/race/:roundId` | Parimutuel — bet on lanes, live race viz |
| `/leaderboard` | Solo + race history, latency stats |
| `/lanes` | CCIP lane benchmark dashboard (API-fed) |

### Features
- Wallet connect (Sepolia + Arbitrum Sepolia)
- Live hop progress via CCIP message status polling
- Animated lane race visualization
- Bet placement + prize pool display
- CCIP Explorer deep links per message

**Exit criteria:** Full solo + parimutuel playable from browser on testnet.

---

## Step 6 — Benchmarking Layer

**Goal:** Real CCIP lane performance data, not just game latency.

1. CRE `lane-benchmark` workflow polls CCIP API `lane-latency` per route
2. Store rolling p50/p95 latency per lane in on-chain `LaneRegistry` or off-chain cache
3. Frontend `/lanes` page: heatmap of lane health, fees, success rate
4. Use benchmark data to weight lane difficulty in race scoring (optional handicap)

**Exit criteria:** Dashboard shows live CCIP lane metrics alongside game results.

---

## Step 7 — Production Hardening

1. Security review (`solidity-auditor` skill on full `contracts/src`)
2. Access control audit on CRE write paths (only forwarder can settle)
3. Gas optimization pass
4. Rate limiting on round creation
5. Emergency pause on `LaneController`
6. Comprehensive integration test suite (Chainlink Local multi-fork)
7. CI: `forge test` + `cre workflow simulate` on PR

---

## Step 8 — Mainnet Path

1. CCIP vNext migration assessment (when public)
2. Mainnet lane selection (high-liquidity routes only)
3. Audit (external or contest)
4. Gradual rollout: solo mode first → parimutuel with capped pools
5. CRE workflows on mainnet DON
6. Monitoring: CCIP Explorer + custom alerts for stuck messages

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

**Step 5:** "Implement Step 5 — Next.js frontend with solo + parimutuel pages on testnet"
