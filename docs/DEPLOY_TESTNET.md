# Testnet Deployment Checklist

Operational guide for CCIP Lane Checker on Ethereum Sepolia, Arbitrum Sepolia, and Base Sepolia.

Canonical addresses and wiring live in `contracts/deployments/testnet.json` (schema v1.2).

**Deployer:** `0x8F83Beb482B95C344cd2FAfb2E2964fabe482483` (keystore name: `laneDeployer`)

---

## Current status

| Phase | Status |
|-------|--------|
| **1 — Deploy contracts** | ✅ Done (all 3 chains) |
| **2 — Peer wiring** | ✅ Done (all 3 chains; verified on-chain) |
| **3 — VRF + funding** | ✅ Done |
| **4 — CRE workflows** | ⬜ **You are here** |
| **5 — Smoke tests** | ⬜ Pending |

---

## Live addresses

| | Ethereum Sepolia | Arbitrum Sepolia | Base Sepolia |
|---|------------------|------------------|--------------|
| **LaneToken** | `0xa159214985Bbb3f7e7A0F986C723262914150ac7` | `0xEA516c219A6Cc6A10a48a186B59Ed2c0240af2Fb` | `0xbd8b72eB19Fea6e25597F40a63Ea1DeF3C600990` |
| **LaneController** | `0xf7a6CAa15Fa51d30439e32E220A507F04611544a` | `0x235850c89c599f80359cE09DC9A29f15DcddaA05` | `0xe8b6dE69e640cfc29672860edDd0e8BA3406F3E1` |
| **LaneExecutor** | `0xbd8b72eB19Fea6e25597F40a63Ea1DeF3C600990` | `0xa159214985Bbb3f7e7A0F986C723262914150ac7` | `0xf2682e839FD4aC8bA60081710ce8689CCcc7e803` |
| **hopRecorder** | `0xbd8b72eB19Fea6e25597F40a63Ea1DeF3C600990` | `0xa159214985Bbb3f7e7A0F986C723262914150ac7` | `0xf2682e839FD4aC8bA60081710ce8689CCcc7e803` |
| **CCIP selector** | `16015286601757825753` | `3478487238524512106` | `10344971235874465080` |
| **CRE forwarder** | `0xF8344CFd5c43616a4366C34E3EEE75af79a74482` | `0x76c9cf548b4179F8901cda1f8623568b58215E62` | `0xF8344CFd5c43616a4366C34E3EEE75af79a74482` |

**Home chain (canonical parimutuel controller):** Ethereum Sepolia — `LaneController` `0xf7a6CAa15Fa51d30439e32E220A507F04611544a`

---

## Wallet setup (every session)

```bash
cd contracts
set -a && source .env && set +a

export DEPLOYER=$(cast wallet address --account laneDeployer)
echo "Deployer: $DEPLOYER"
```

Forge keystore broadcasts need **both** `--account laneDeployer` (signer) and `--sender $DEPLOYER` (simulation address).

Alternative: export `PRIVATE_KEY=0x...` in `.env` and omit `--account` / `--sender` (see `BroadcastScript.sol`).

---

## Phase 3 — VRF subscriptions + native funding

Do this on **each chain** before solo play or CRE hop-sender traffic.

### 3a — VRF v2.5 consumer (per chain)

At [vrf.chain.link](https://vrf.chain.link), on each network:

1. Create or open a subscription.
2. **Add consumer** → paste that chain's `LaneToken` address (table above).
3. Fund subscription with **5–10 LINK**.
4. Record subscription ID in `contracts/deployments/testnet.json` → `chains.<network>.infra.vrfSubscriptionId`.

| Chain | LaneToken to register |
|-------|----------------------|
| Sepolia | `0xa159214985Bbb3f7e7A0F986C723262914150ac7` |
| Arbitrum Sepolia | `0xEA516c219A6Cc6A10a48a186B59Ed2c0240af2Fb` |
| Base Sepolia | `0xbd8b72eB19Fea6e25597F40a63Ea1DeF3C600990` |

Without VRF consumer + LINK, `LaneToken.startGame` will never receive a callback.

Run each `cast send` **one at a time** (do not paste the whole block — bash treats `#` comments and trailing `\` badly). `--slow` is for `forge script` only, not `cast send`. If Base gas fails, add `--gas-price 100000000`.

Executors pay CCIP in native token. Plain transfer to the executor address.

```bash
# Sepolia executor — ~0.05 ETH
cast send 0xbd8b72eB19Fea6e25597F40a63Ea1DeF3C600990 \
  --value 0.05ether \
  --rpc-url $SEPOLIA_RPC \
  --account laneDeployer

# Arbitrum Sepolia executor — ~0.02 ETH
cast send 0xa159214985Bbb3f7e7A0F986C723262914150ac7 \
  --value 0.02ether \
  --rpc-url $ARBITRUM_SEPOLIA_RPC \
  --account laneDeployer

# Base Sepolia executor — ~0.02 ETH
cast send 0xf2682e839FD4aC8bA60081710ce8689CCcc7e803 \
  --value 0.02ether \
  --rpc-url $BASE_SEPOLIA_RPC \
  --account laneDeployer
```

### 3c — Fund LaneTokens (solo CCIP outbound)

```bash
cast send 0xa159214985Bbb3f7e7A0F986C723262914150ac7 \
  --value 0.02ether --rpc-url $SEPOLIA_RPC --account laneDeployer

cast send 0xEA516c219A6Cc6A10a48a186B59Ed2c0240af2Fb \
  --value 0.01ether --rpc-url $ARBITRUM_SEPOLIA_RPC --account laneDeployer

cast send 0xbd8b72eB19Fea6e25597F40a63Ea1DeF3C600990 \
  --value 0.01ether --rpc-url $BASE_SEPOLIA_RPC --account laneDeployer
```

### 3d — Balance checks

```bash
cast balance 0xbd8b72eB19Fea6e25597F40a63Ea1DeF3C600990 --rpc-url $SEPOLIA_RPC
cast balance 0xa159214985Bbb3f7e7A0F986C723262914150ac7 --rpc-url $ARBITRUM_SEPOLIA_RPC
cast balance 0xf2682e839FD4aC8bA60081710ce8689CCcc7e803 --rpc-url $BASE_SEPOLIA_RPC
```

Refill when Sepolia executor drops below **0.01 ETH** or L2 executors below **0.005 ETH**. See `docs/PRE_DEPLOY_RUNBOOK.md` for sizing notes.

### 3e — Optional: tune `minBet`

```bash
# Example: 0.1 LINK minimum on home controller
cast send 0xf7a6CAa15Fa51d30439e32E220A507F04611544a \
  "setMinBet(uint256)" 100000000000000000 \
  --rpc-url $SEPOLIA_RPC \
  --account laneDeployer
```

### Phase 3 checklist

- [x] VRF consumer added + LINK funded (Sepolia)
- [x] VRF consumer added + LINK funded (Arbitrum Sepolia)
- [x] VRF consumer added + LINK funded (Base Sepolia)
- [x] `vrfSubscriptionId` recorded in `testnet.json` (each chain)
- [x] Executors funded with native ETH
- [x] LaneTokens funded with native ETH
- [x] CCIP lanes confirmed at [ccip.chain.link](https://ccip.chain.link) for all three selectors

---

## Phase 4 — CRE workflows

Staging configs are pre-filled with live addresses. Confirm before DON deploy:

| Workflow | Config file | Key address |
|----------|-------------|-------------|
| hop-sender (Sepolia origin) | `cre/lane-checker-cre/hop-sender/config.staging.json` | executor `0xbd8b72eB19Fea6e25597F40a63Ea1DeF3C600990` |
| hop-sender (Arbitrum) | `cre/lane-checker-cre/hop-sender/config.staging.arbitrum-sepolia.json` | executor `0xa159214985Bbb3f7e7A0F986C723262914150ac7` |
| hop-sender (Base) | `cre/lane-checker-cre/hop-sender/config.staging.base-sepolia.json` | executor `0xf2682e839FD4aC8bA60081710ce8689CCcc7e803` |
| round-scheduler | `cre/lane-checker-cre/round-scheduler/config.staging.json` | controller `0xf7a6CAa15Fa51d30439e32E220A507F04611544a` |
| hop-monitor | `cre/lane-checker-cre/hop-monitor/config.staging.json` | controller `0xf7a6CAa15Fa51d30439e32E220A507F04611544a` |
| settlement | `cre/lane-checker-cre/settlement/config.staging.json` | controller `0xf7a6CAa15Fa51d30439e32E220A507F04611544a` |
| sweep-unclaimed | `cre/lane-checker-cre/sweep-unclaimed/config.staging.json` | controller `0xf7a6CAa15Fa51d30439e32E220A507F04611544a` |

```bash
# Must run from the CRE project root (where project.yaml lives), NOT contracts/
cd cre/lane-checker-cre
cre login

# Cron workflows — fire once immediately in simulation
cre workflow simulate hop-sender --target staging-settings
cre workflow simulate hop-sender --target staging-arbitrum-sepolia-settings
cre workflow simulate hop-sender --target staging-base-sepolia-settings
cre workflow simulate round-scheduler --target staging-settings

# EVM log workflows — wait for a matching onchain event, or pass a known tx:
# cre workflow simulate settlement --target staging-settings --timeout 120s
# cre workflow simulate hop-monitor --target staging-settings --timeout 120s
# After Phase 5 produces WinnerDeclared / HopCompleted logs, non-interactive replay:
# cre workflow simulate settlement --target staging-settings --non-interactive --trigger-index 0 \
#   --evm-tx-hash 0x... --evm-event-index 0
```

If you are already in `contracts/`, either `cd ../cre/lane-checker-cre` or pass `--project-root ../cre/lane-checker-cre` on every `cre` command.

Deploy to testnet DON only after Phase 3 funding is complete.

```bash
# From repo root, if ABIs changed:
./scripts/sync-cre-abis.sh
```

### Phase 4 checklist

- [ ] All `cre workflow simulate` commands pass
- [ ] hop-sender deployed (3 targets: Sepolia, Arbitrum, Base)
- [ ] round-scheduler, hop-monitor, settlement, sweep-unclaimed deployed
- [ ] Frontend `.env.local` points at `testnet.json` addresses (or `NEXT_PUBLIC_*` overrides)

---

## Phase 5 — Smoke tests

### Automated manual path (no CRE DON)

Use the owner-operated script when CRE deployment access is unavailable. It mirrors CRE
`round-scheduler` + `hop-sender` + `settlement` using deployer transactions on all three chains.

```bash
# Ensure deployer holds LINK on Sepolia for optional bets (default 0.2 LINK × 2 lanes)
cd contracts && set -a && source .env && set +a
export DEPLOYER=$(cast wallet address --account laneDeployer)

# Full run (createRound → bet → startRace → CCIP hop loop → settle → claim)
../scripts/manual-parimutuel-smoke.sh run-all

# Or step-by-step:
../scripts/manual-parimutuel-smoke.sh setup
../scripts/manual-parimutuel-smoke.sh bet 0
../scripts/manual-parimutuel-smoke.sh bet 1
../scripts/manual-parimutuel-smoke.sh start
../scripts/manual-parimutuel-smoke.sh drive    # loops hops until Finished (~1 min CCIP wait/iter)
../scripts/manual-parimutuel-smoke.sh settle
../scripts/manual-parimutuel-smoke.sh claim
../scripts/manual-parimutuel-smoke.sh status
```

`SKIP_BETS=1` skips betting in `run-all`. `CCIP_WAIT_SEC` (default 60) controls pause between hop iterations.

### Interactive frontend (replaces shell for operators + bettors)

```bash
cd frontend
cp .env.example .env.local   # optional — addresses load from testnet.json
npm install && npm run dev
```

Open `http://localhost:3000`, connect **laneDeployer** wallet on Sepolia:

| Role | UI |
|------|-----|
| **Owner** (`laneDeployer`) | **Race Control** panel on `/race/{id}` — Create round → Start race → Send hops (switch chain as prompted) → Settle |
| **Bettor** | Approve LINK → Bet on lane 0 or 1 → Claim after settle |
| **Everyone** | Live lane progress from `getLane()` (polls every 3s) |

The operator panel mirrors `scripts/manual-parimutuel-smoke.sh` without shell access.

### Solo (Sepolia)

1. Approve LINK → `LaneToken.deposit(amount)` on `0xa159214985Bbb3f7e7A0F986C723262914150ac7`.
2. `startGame` with a valid 3-chain lane path.
3. Confirm VRF callback, then CCIP hop events across chains.
4. Confirm settlement on home controller `0xf7a6CAa15Fa51d30439e32E220A507F04611544a`.

### Parimutuel (Sepolia home)

1. `createRound` (manual or wait for `round-scheduler` CRON).
2. Players `buyLaneTokens` on Sepolia controller.
3. `startRace` → CRE `hop-sender` drives hops on each chain.
4. Confirm `HopCompleted` / `LaneFinished` on Sepolia controller.
5. `settlement` workflow → `distributePrizes`; bettors call `claimPrize(roundId)`.

### Phase 5 checklist

- [ ] Solo game completes end-to-end
- [ ] Parimutuel round completes end-to-end
- [ ] CCIP message status visible (frontend or explorer)
- [ ] No `UnknownDestination` / `UnauthorizedSource` reverts

---

## Verify peer wiring (spot checks)

Already confirmed: Sepolia executor → Arbitrum peer returns `0xa159214985Bbb3f7e7A0F986C723262914150ac7`.

```bash
# Sepolia executor → Base peer
cast call 0xbd8b72eB19Fea6e25597F40a63Ea1DeF3C600990 \
  "remoteExecutors(uint64)(address)" 10344971235874465080 \
  --rpc-url $SEPOLIA_RPC
# expect: 0xf2682e839FD4aC8bA60081710ce8689CCcc7e803

# Sepolia LaneToken → Arbitrum peer token
cast call 0xa159214985Bbb3f7e7A0F986C723262914150ac7 \
  "remoteLaneTokens(uint64)(address)" 3478487238524512106 \
  --rpc-url $SEPOLIA_RPC
# expect: 0xEA516c219A6Cc6A10a48a186B59Ed2c0240af2Fb

# Hop recorder wired
cast call 0xf7a6CAa15Fa51d30439e32E220A507F04611544a \
  "hopRecorders(address)(bool)" 0xbd8b72eB19Fea6e25597F40a63Ea1DeF3C600990 \
  --rpc-url $SEPOLIA_RPC
# expect: true
```

---

## Appendix — completed phases (reference)

<details>
<summary>Phase 1 — Deploy (done)</summary>

```bash
export DEPLOYER=$(cast wallet address --account laneDeployer)

# Per chain: DEPLOY_CHAIN=sepolia|arbitrum-sepolia|base-sepolia
# VRF_SUBSCRIPTION_ID=<per-chain-id>
# Required unless local: CRE_WORKFLOW_OWNER and/or CRE_WORKFLOW_ID
# (or CRE_ALLOWLIST_OPTIONAL=true for local-only deploys)
forge script script/DeployAll.s.sol:DeployAll \
  --rpc-url $SEPOLIA_RPC \
  --account laneDeployer \
  --sender $DEPLOYER \
  --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY \
  -vvvv
```

Base deploy needed `--slow` and `--resume` after initial `gapped-nonce` failure.

</details>

<details>
<summary>Phase 2 — Peer wiring (done)</summary>

Wire-only on each chain with `WIRE_ONLY=true` and `EXISTING_LANE_*` / `REMOTE_*` env vars. Example (Sepolia):

```bash
export DEPLOY_CHAIN=sepolia
export WIRE_ONLY=true
export EXISTING_LANE_TOKEN=0xa159214985Bbb3f7e7A0F986C723262914150ac7
export EXISTING_LANE_CONTROLLER=0xf7a6CAa15Fa51d30439e32E220A507F04611544a
export EXISTING_LANE_EXECUTOR=0xbd8b72eB19Fea6e25597F40a63Ea1DeF3C600990
export REMOTE_EXECUTOR_ARBITRUM_SEPOLIA=0xa159214985Bbb3f7e7A0F986C723262914150ac7
export REMOTE_EXECUTOR_BASE_SEPOLIA=0xf2682e839FD4aC8bA60081710ce8689CCcc7e803
export REMOTE_LANE_TOKEN_ARBITRUM_SEPOLIA=0xEA516c219A6Cc6A10a48a186B59Ed2c0240af2Fb
export REMOTE_LANE_TOKEN_BASE_SEPOLIA=0xbd8b72eB19Fea6e25597F40a63Ea1DeF3C600990

forge script script/DeployAll.s.sol:DeployAll \
  --rpc-url $SEPOLIA_RPC \
  --account laneDeployer \
  --sender $DEPLOYER \
  --broadcast -vvvv
```

Repeat for Arbitrum Sepolia and Base Sepolia (Base: add `--slow`).

</details>

---

## Environment reference

| Variable | Required | Description |
|----------|----------|-------------|
| `DEPLOYER` | Keystore path | `cast wallet address --account laneDeployer` |
| `PRIVATE_KEY` | Alt to keystore | Deployer hex key (never commit) |
| `SEPOLIA_RPC` | Yes | Sepolia JSON-RPC |
| `ARBITRUM_SEPOLIA_RPC` | Yes | Arbitrum Sepolia JSON-RPC |
| `BASE_SEPOLIA_RPC` | Yes | Base Sepolia JSON-RPC |
| `ETHERSCAN_API_KEY` | For `--verify` | Etherscan / Arbiscan / Basescan |
| `DEPLOY_CHAIN` | Deploy/wire scripts | `sepolia`, `arbitrum-sepolia`, `base-sepolia` |
| `VRF_SUBSCRIPTION_ID` | Phase 1 deploy only | Per-chain VRF v2.5 subscription |
| `WIRE_ONLY` | Phase 2 | `true` to wire existing contracts |
| `EXISTING_LANE_*` | Phase 2 | Local contract addresses |
| `REMOTE_EXECUTOR_*` | Phase 2 | Peer executor per chain |
| `REMOTE_LANE_TOKEN_*` | Phase 2 | Peer LaneToken per chain |

**Forge keystore pattern:** always `--account laneDeployer` (literal name) + `--sender $DEPLOYER`.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `a value is required for '--account'` | Use `--account laneDeployer` literally; ensure `DEPLOYER` is exported |
| `You seem to be using Foundry's default sender` | `export DEPLOYER=$(cast wallet address --account laneDeployer)` + `--sender $DEPLOYER` |
| `gapped-nonce` on Base | `--slow`; `cast nonce $DEPLOYER --rpc-url $BASE_SEPOLIA_RPC`; `--resume` |
| `UnknownDestination` on `sendHop` | Re-run Phase 2 wire on origin chain |
| `UnauthorizedSource` on CCIP receive | Mismatched `remoteExecutors` |
| CRE `NotAuthorized` | `creForwarder` / `hopSenders` not set on executor |
| CCIP send fails | Fund executor with more native ETH |
| VRF callback stuck | Add LaneToken as consumer; fund LINK |
