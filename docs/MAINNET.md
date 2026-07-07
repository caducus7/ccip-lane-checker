# Mainnet Path — Step 8 Checklist

Pre-mainnet checklist for CCIP Lane Checker. Complete after testnet E2E (Steps 4–6) and production hardening (Step 7).

---

## Prerequisites

- [ ] Testnet smoke tests pass on Sepolia, Arbitrum Sepolia, and Base Sepolia
- [ ] CRE workflows validated on testnet DON (`round-scheduler`, `hop-monitor`, `settlement`)
- [ ] Security review complete (`solidity-auditor` on full `contracts/src`)
- [ ] External audit or contest (recommended for parimutuel pools)
- [ ] Emergency pause wired on `LaneController` via `LaneControllerPausable` (`contracts/src/security/Pausable.sol`)

---

## CCIP vNext Migration Assessment

CCIP vNext is not yet public. The codebase abstracts transport behind `IRouterClient` / `ICcipRouter` so migration is primarily a config and adapter swap.

When vNext is available:

1. **Router swap** — Update `ChainConfig` / deployment JSON with vNext router addresses per chain.
2. **Message schema** — Re-verify `Client.EVM2AnyMessage` and `extraArgs` encoding if the vNext schema changes.
3. **Lane allowlisting** — Re-run CCIP lane allowlist configuration for mainnet routes.
4. **Local regression** — Re-run Chainlink Local multi-fork integration tests with the new simulator.
5. **CRE workflows** — Confirm EVM log triggers and write paths against vNext event signatures.
6. **Frontend** — Update CCIP Explorer deep links and message status polling if API surfaces change.

**Expected impact:** Game logic (`LaneToken`, `LaneController`, prize math) should not change — only the CCIP transport layer and infra addresses.

See also [IMPLEMENTATION.md](./IMPLEMENTATION.md#ccip-vnext-migration-notes).

---

## Mainnet Lane Selection

Prefer high-liquidity, well-monitored CCIP routes only:

| Priority | Route examples | Rationale |
|----------|----------------|-----------|
| Tier 1 | Ethereum ↔ Arbitrum, Ethereum ↔ Base | Highest CCIP volume, best lane monitoring |
| Tier 2 | Ethereum ↔ Optimism, Arbitrum ↔ Base | Strong liquidity, lower latency variance |
| Avoid initially | Long-tail L2/L1 pairs | Higher stuck-message risk, thin fee markets |

Document selected lanes in `contracts/deployments/mainnet.json` (create at Step 8).

---

## Gradual Rollout

1. **Phase 1 — Solo mode only**
   - Deploy `LaneToken` on 2–3 mainnet chains
   - No real-money parimutuel pools
   - CRE monitors hops; no settlement writes beyond solo leaderboard

2. **Phase 2 — Capped parimutuel**
   - Deploy `LaneController` + `LaneExecutor` on home chain + executors per lane chain
   - Hard-cap pool size and per-wallet bet limits
   - CRE forwarder-only settlement (access control audit)

3. **Phase 3 — Full product**
   - Raise caps based on audit findings and operational metrics
   - Enable benchmark-weighted lane scoring (optional)

---

## Infrastructure

### VRF v2.5

- [ ] Create mainnet subscription per chain at [vrf.chain.link](https://vrf.chain.link)
- [ ] Fund subscriptions with LINK
- [ ] Add deployed consumers (`LaneToken`) to each subscription

### CCIP

- [ ] Confirm outbound/inbound lanes between all deployed chains ([CCIP Directory — Mainnet](https://docs.chain.link/ccip/directory/mainnet))
- [ ] Fund contracts with LINK for CCIP fees
- [ ] Register tokens if using CCT (Cross-Chain Token) pattern

### CRE

- [ ] Deploy workflows to mainnet DON
- [ ] Restrict write paths: only CRE forwarder may call `declareWinner` / `distributePrizes`
- [ ] Set CRON schedules appropriate for mainnet (not 30-min testnet cadence)

---

## Monitoring & Operations

- [ ] CCIP Explorer alerts for stuck messages (> N minutes)
- [ ] Custom dashboard: round state, pool balances, VRF subscription balance
- [ ] Runbook: emergency pause procedure (`LaneController.pause()`)
- [ ] Runbook: stuck race / manual winner declaration (multisig-only)

---

## Deployment Commands (reference)

```bash
# Per chain — user-run only; never commit keys
cd contracts
source .env

DEPLOY_CHAIN=sepolia VRF_SUBSCRIPTION_ID=<id> \
  forge script script/DeployAll.s.sol:DeployAll \
  --rpc-url $SEPOLIA_RPC --broadcast --verify

DEPLOY_CHAIN=arbitrum-sepolia VRF_SUBSCRIPTION_ID=<id> \
  forge script script/DeployAll.s.sol:DeployAll \
  --rpc-url $ARBITRUM_SEPOLIA_RPC --broadcast --verify

DEPLOY_CHAIN=base-sepolia VRF_SUBSCRIPTION_ID=<id> \
  forge script script/DeployAll.s.sol:DeployAll \
  --rpc-url $BASE_SEPOLIA_RPC --broadcast --verify
```

After each deploy, update `contracts/deployments/mainnet.json` and `frontend/.env` with verified addresses.

---

## Sign-off

| Gate | Owner | Status |
|------|-------|--------|
| Contract audit | — | Pending |
| CRE mainnet DON | — | Pending |
| Multisig ownership transfer | — | Pending |
| Pause drill tested | — | Pending |
| Mainnet deploy | — | Pending |
