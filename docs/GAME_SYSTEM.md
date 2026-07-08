# CCIP Lane Checker — System & Game Guide

Gamified cross-chain benchmarking: race tokens across CCIP-connected chains, measure real latency, and (in parimutuel mode) bet on which lane finishes first.

This document explains **what the system does**, **how the two game modes work**, **how contracts interact**, and **what trusted roles exist**. For deployment steps, see [SEPOLIA_DEPLOYMENT_GUIDE.md](./SEPOLIA_DEPLOYMENT_GUIDE.md).

---

## High-level architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  Players / CRE (Chainlink Runtime Environment)                   │
│  Solo: deposit → startGame    Parimutuel: buyLaneTokens → claim │
└────────────┬───────────────────────────────┬────────────────────┘
             │                               │
     ┌───────▼────────┐              ┌───────▼────────┐
     │   LaneToken    │              │ LaneController │  ← canonical home chain (Sepolia)
     │  (solo mode)   │              │ (parimutuel)   │
     └───────┬────────┘              └───────┬────────┘
             │ CCIP tokens + hops            │ hop state only
             │                               │
     ┌───────▼───────────────────────────────▼────────┐
     │         LaneExecutor (one per chain)          │
     │  sendHop → CCIP → peer executor → recordHop   │
     └───────────────────────┬────────────────────────┘
                             │ CCIP messaging
              ┌──────────────┼──────────────┐
              ▼              ▼              ▼
         Sepolia      Arbitrum Sepolia   Base Sepolia
```

| Component | Role |
|-----------|------|
| **LaneToken** | Solo challenge: shared deposit pool, VRF-random hop routing, CCIP token bridges between peer `LaneToken` deployments |
| **LaneController** | Parimutuel: betting pool, lane progress, winner/runner-up, prize split, pull claims |
| **LaneExecutor** | Per-chain CCIP relay: sends hop messages along a lane circuit and reports hops to the home `LaneController` |
| **CRE workflows** | Off-chain orchestration: schedule rounds, send hops, settle prizes, sweep unclaimed dust, poll CCIP benchmarks |
| **Frontend** | Wallet UX for solo + parimutuel; reads `testnet.json` addresses |

**Home chain:** Ethereum Sepolia is the **canonical** chain for parimutuel settlement. `LaneExecutor` on spoke chains relay hop receipts to the Sepolia home executor, which calls `LaneController.recordHop`. Solo games can start on any wired chain but share the same CCIP + VRF infrastructure.

---

## Supported testnets

| Network | Chain ID | CCIP selector |
|---------|----------|---------------|
| Ethereum Sepolia | `11155111` | `16015286601757825753` |
| Arbitrum Sepolia | `421614` | `3478487238524512106` |
| Base Sepolia | `84532` | `10344971235874465080` |

Canonical router, VRF, LINK, and CRE forwarder addresses live in `contracts/src/libraries/ChainConfig.sol` and `contracts/deployments/testnet.json`.

---

## Game mode 1 — Solo challenge (`LaneToken`)

### What the player experiences

1. **Deposit** ERC20 into the shared `LaneToken` pool (on testnet deploy this is **LINK**).
2. **Start a game** with a stake amount and `maxHops` (1–16). The first hop bridges tokens to a VRF-selected remote chain (or loops locally if wired to self).
3. **Watch hops** complete via CCIP; each hop increments `hopCount` on the chain that receives the message.
4. **Finish** when `hopCount >= maxHops` on a chain — stake returns to the initiator’s **booked balance** on that chain (once per `foreignKey` globally).
5. **Withdraw** booked balance back to wallet.

Leaderboard ranking uses cumulative **latency** (`totalLatency`) across hops — lower is better.

### On-chain lifecycle

```
deposit(amount)
  → s_balances[user] += amount, s_totalBooked += amount

startGame(destSelector, amount, maxHops)
  → move amount from booked → tokensInPlay
  → create GameRound with foreignKey = keccak256(chainId, this, gameId)
  → CCIP bridge tokens + hop payload to remote LaneToken

_ccipReceive (inbound hop)
  → verify sender == remoteLaneTokens[source]
  → verify token amounts match payload
  → bootstrap game if foreignKey unseen, else validate GameMismatch fields
  → _recordHop: increment hopCount, add latency

hopCount >= maxHops
  → credit initiator booked balance (once per foreignKey)
  → propagate settlement message to peer chains (prevents double payout)
  → if more hops needed: request VRF → fulfillRandomWords → _bridge to next chain
```

### Cross-chain rules (important)

- Games are linked by **`foreignKey`** across chains (origin chain ID + origin token address + origin game ID).
- Each chain tracks its own **`hopCount`**, but **only one chain may pay out** per `foreignKey` (`s_foreignKeySettled`).
- After tokens **bridge out**, origin `abandonGame` is blocked until the game resolves on a peer or times out (7-day `GAME_ABANDON_TIMEOUT` on chains where the game stays active).
- VRF picks the next chain from `supportedChainSelectors`; every selector must have `remoteLaneTokens[selector]` wired or VRF fulfillment reverts.

### Token requirements

- Standard ERC20 only (no fee-on-transfer). Deploy uses Chainlink **LINK** on testnets.
- `LaneToken` needs **native ETH** on each chain for CCIP send fees (`receive()` accepts deposits).

---

## Game mode 2 — Parimutuel race (`LaneController`)

### What the player experiences

1. **Wait for a round** — CRE `round-scheduler` creates a round with two predefined lane circuits (different chain paths), or an operator creates one manually.
2. **Bet** during the **Betting** phase: pick lane 0 or 1, stake LINK (minimum `minBet`, default `1e6` base units — tune via `setMinBet` for 18-decimal LINK).
3. **Race starts** — betting closes; CRE `hop-sender` dispatches CCIP hops along each lane’s `chainPath`.
4. **First lane to complete all hops wins**; second finisher is **runner-up** (if it finishes before timeout).
5. After settlement, **claim** winner and/or runner-up shares via `claimPrize(roundId)`.

### Round state machine

```
Betting → Racing → Finished → Settled
```

| State | Meaning |
|-------|---------|
| **Betting** | `buyLaneTokens` open |
| **Racing** | Hops recorded; first finisher triggers **Finished** |
| **Finished** | Winner declared; runner-up may still be racing; hops still accepted for runner-up lane |
| **Settled** | `distributePrizes` ran; bettors pull claims; later `sweepUnclaimed` sends dust to treasury |

### Winner & runner-up

- **Winner** = first lane where `hopsCompleted >= requiredHops` (set in `createRound` from path length).
- **Runner-up** = second lane to finish (if any).
- `recordHop` **auto-declares** the winner on first finish and snapshots `runnerUpSettlementTimeout` (default 7 days). CRE `declareWinner` exists as fallback only.
- If the winning lane has **no bets** (or dust below `minBet`), the **70% winner share** redirects to the highest-pool other lane.

### Prize split (`PrizeCalculator`)

| Recipient | Share |
|-----------|-------|
| Winner lane bettors (pro-rata) | 70% |
| Platform treasury | 15% |
| Gas reserve | 10% |
| Runner-up lane bettors (pro-rata) | 5% (remainder after floor division) |

Claims are **pull-based**: `claimPrize` transfers LINK from the controller to the bettor. Unclaimed shares can be swept to treasury after `claimWindow` (default 7 days) from settlement time.

### Parimutuel hop flow

```
CRE hop-sender → LaneExecutor.sendHop(roundId, laneId, destSelector)
  → CCIP to peer executor

Peer/home LaneExecutor._ccipReceive
  → validate messageId dedup, remote sender, pause state
  → if home chain: LaneController.recordHop(roundId, laneId, hopChainSelector, sendTime)
  → if spoke: relay CCIP to home executor

LaneController.recordHop
  → verify hopRecorder, chainSelector matches lane.chainPath[hopsCompleted]
  → latency = min(block.timestamp - sendTime, 30 days)
  → on final hop: mark lane finished; first finisher wins
```

**Latency does not pick the winner** — only **finish order** matters. Latency is tracked for stats/leaderboards.

---

## `LaneExecutor` — per-chain relay

Each chain runs one `LaneExecutor` wired to:

- Local `LaneController` (for home chain direct `recordHop`)
- `homeChainSelector` + `canonicalController` + `homeExecutor` (for spoke → home relay)
- `remoteExecutors[peerSelector]` — expected CCIP sender on inbound messages
- `hopSenders` — who may call `sendHop` (CRE forwarder + owner)
- `creForwarder` — who may call `onReport` (allowlisted calldata only)

**Fees:** Every `sendHop` pays CCIP fees in **native ETH** from the executor balance. Keep executors funded (see [PRE_DEPLOY_RUNBOOK.md](./PRE_DEPLOY_RUNBOOK.md)).

---

## CRE orchestration

| Workflow | Trigger | Action |
|----------|---------|--------|
| **round-scheduler** | CRON (every 30 min staging) | `createRound` + `startRace` on Sepolia controller |
| **hop-sender** | CRON + `HopReceived` logs | `LaneExecutor.sendHop` for next leg |
| **hop-monitor** | `HopCompleted` / `LaneFinished` logs | Observability (winner is on-chain via `recordHop`) |
| **settlement** | `WinnerDeclared` | `distributePrizes` |
| **sweep-unclaimed** | CRON (every 6 h staging) | `sweepUnclaimed` for rounds past claim window |
| **lane-benchmark** | CRON (every 5 min) | CCIP API latency → `POST /api/lanes` |

CRE writes use the network **Keystone Forwarder** (`creForwarder`). The forwarder calls `onReport` on contracts; `CreReportAuth` allowlists selectors (`createRound`, `startRace`, `distributePrizes`, `sweepUnclaimed`, `sendHop`, etc.).

---

## Roles & trust model

| Role | Who | Powers |
|------|-----|--------|
| **Owner** (`LaneController`, `LaneExecutor`) | Deployer multisig | Pause, config (`minBet`, `claimWindow`, cooldown), `setHopRecorder`, `setCreForwarder` |
| **Admin** (`LaneToken`) | Deployer | `setRemoteLaneToken`, `transferAdmin` |
| **CRE forwarder** | Chainlink Keystone | `onReport` → gated admin calls |
| **Hop recorder** | Wired `LaneExecutor` only (one active) | `recordHop` on home controller |
| **Hop sender** | CRE forwarder | `sendHop` on executors |
| **Players** | Anyone | `deposit`, `startGame`, `buyLaneTokens`, `claimPrize`, `withdraw` |

Players cannot call privileged paths. Mis-wiring `remoteExecutors` / `remoteLaneTokens` or stale hop recorder/sender entries are **operational risks**, not player-exploitable paths if deploy checklist is followed.

---

## Security properties (tested)

- **Solvency:** Controller balance covers pools + unclaimed shares; LaneToken `balance >= totalBooked + tokensInPlay` per chain.
- **Single settlement:** One `foreignKey` payout across solo cross-chain games.
- **Prize conservation:** 70/15/10/5 split sums exactly to pool; claim caps prevent over-withdrawal.
- **CCIP dedup:** Duplicate `messageId` rejected on executor and LaneToken.
- **Pause:** Entry points respect `whenNotPaused`; claims intentionally work while paused so users can exit.
- **minBet:** Blocks dust bets that could capture winner share; dust lanes treated as empty for payout redirect.

Regression tests: `contracts/test/audit/`, `contracts/test/integration/`, Fizz invariant suite (`contracts/test/fizz/`).

---

## Frontend integration

- Betting token is **ERC20** — users must `approve` before `buyLaneTokens` or `deposit`.
- `getRoundWinner` returns `255` when unset (`NO_LANE`) — never check `=== 0`.
- Addresses and selectors: `contracts/deployments/testnet.json`, `frontend/.env.example`.
- CCIP Explorer links built in `HopProgress` component for live message tracking.

---

## Related docs

| Doc | Purpose |
|-----|---------|
| [SEPOLIA_DEPLOYMENT_GUIDE.md](./SEPOLIA_DEPLOYMENT_GUIDE.md) | Wallet setup, deploy, wire, smoke tests |
| [DEPLOY_TESTNET.md](./DEPLOY_TESTNET.md) | Checklist-style deploy reference |
| [PRE_DEPLOY_RUNBOOK.md](./PRE_DEPLOY_RUNBOOK.md) | Funding sizes, VRF, CCIP fee ballparks |
| [CONSOLIDATION.md](./CONSOLIDATION.md) | Cross-stack ABI/sync rules |
| [IMPLEMENTATION.md](./IMPLEMENTATION.md) | Build roadmap & step completion |
