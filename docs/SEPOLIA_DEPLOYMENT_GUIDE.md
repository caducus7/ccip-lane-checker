# Sepolia Testnet — Full Deployment & First Tests

Start-to-finish guide: wallet setup in the terminal, deploy on **Ethereum Sepolia**, **Arbitrum Sepolia**, and **Base Sepolia**, wire cross-chain peers, configure CRE, and run your first solo + parimutuel smoke tests.

**Pair with:** [GAME_SYSTEM.md](./GAME_SYSTEM.md) (how the game works), [PRE_DEPLOY_RUNBOOK.md](./PRE_DEPLOY_RUNBOOK.md) (funding sizes).

> **Never commit private keys.** Use a dedicated testnet deployer wallet. Add `.env` to `.gitignore` (already configured).

---

## Deployment status (live testnet)

**Phases 1–2 complete.** Deployer `0x8F83Beb482B95C344cd2FAfb2E2964fabe482483` (keystore `laneDeployer`).

| Phase | Status |
|-------|--------|
| Deploy contracts (3 chains) | ✅ |
| Cross-chain peer wiring | ✅ |
| VRF + funding | ✅ |
| CRE workflows | ⬜ **Next** |
| Smoke tests | ⬜ |

**Operational checklist (current work):** [DEPLOY_TESTNET.md](./DEPLOY_TESTNET.md) — Phase 4 (CRE) and Phase 5 (smoke). Operator UI + `scripts/manual-parimutuel-smoke.sh` work without a CRE DON.

**Home controller (Sepolia):** `0xf7a6CAa15Fa51d30439e32E220A507F04611544a`

Steps 3–4 below are **reference** for how deploy/wire was done. Skip to **Step 5** (CRE) or run the Phase 5 smoke path in `DEPLOY_TESTNET.md`.

---

## What you will deploy

| Chain | Contracts |
|-------|-----------|
| Each of 3 testnets | `LaneToken`, `LaneController`, `LaneExecutor` |
| Sepolia (home) | Canonical `LaneController` for parimutuel settlement |
| All chains | Peer wiring: `remoteExecutors`, `remoteLaneTokens`, CRE forwarder |

---

## Prerequisites

### Software

```bash
# Foundry (forge, cast, anvil)
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Verify
forge --version
cast --version

# CRE CLI (for workflow simulate/deploy later)
# See https://docs.chain.link/cre/getting-started
cre version
```

### Accounts & faucets

| Need | Where |
|------|-------|
| Sepolia ETH | [sepoliafaucet.com](https://sepoliafaucet.com), Alchemy faucet, etc. |
| Arbitrum Sepolia ETH | [faucet.quicknode.com/arbitrum/sepolia](https://faucet.quicknode.com/arbitrum/sepolia) |
| Base Sepolia ETH | [coinbase.com/faucets](https://www.coinbase.com/faucets/base-ethereum-sepolia-faucet) |
| Testnet LINK (per chain) | [faucets.chain.link](https://faucets.chain.link) |
| VRF v2.5 subscription (per chain) | [vrf.chain.link](https://vrf.chain.link) |

Budget for deployer wallet: **~0.15 ETH total** across three chains + **5–10 LINK per chain** for VRF/solo play.

### RPC URLs

Copy the template and fill in provider URLs if you use Alchemy/Infura:

```bash
cd /path/to/ccip-lane-checker/contracts
cp .env.example .env
```

Edit `contracts/.env`:

```bash
SEPOLIA_RPC=https://ethereum-sepolia-rpc.publicnode.com
ARBITRUM_SEPOLIA_RPC=https://sepolia-rollup.arbitrum.io/rpc
BASE_SEPOLIA_RPC=https://sepolia.base.org
ETHERSCAN_API_KEY=your_key   # optional, for --verify
```

Load env in every terminal session:

```bash
cd contracts
set -a && source .env && set +a
```

---

## Step 1 — Import deployer wallet in terminal

You need the deployer private key available to `forge script`. Three supported patterns:

### Option A — `PRIVATE_KEY` env var (simplest)

Export directly in the shell (session-only; not written to disk):

```bash
export PRIVATE_KEY=0xYOUR_64_HEX_CHARS_NO_SPACES
cast wallet address --private-key $PRIVATE_KEY
# Note the address — fund it on all three testnets
```

To persist locally **outside git**, append to `contracts/.env` (never commit):

```bash
echo 'PRIVATE_KEY=0x...' >> contracts/.env
```

### Option B — Foundry keystore (recommended for repeated use)

Import interactively (prompts for key; stores encrypted under `~/.foundry/keystores/`):

```bash
cast wallet import deployer --interactive
# Enter private key when prompted, then set a keystore password
```

Verify and fund:

```bash
cast wallet address --account deployer
# 0xYourDeployerAddress
```

Use with Forge via `--account` (no `PRIVATE_KEY` in env). `cast wallet address` needs `--account`; a bare name is treated as a raw private key.

```bash
export DEPLOYER=$(cast wallet address --account deployer)   # prompts for keystore password
forge script script/DeployAll.s.sol:DeployAll \
  --rpc-url $SEPOLIA_RPC \
  --account deployer \
  --sender $DEPLOYER \
  --broadcast --verify -vvvv
```

Alternatively, export the key for this session only (prompts for keystore password):

```bash
export PRIVATE_KEY=$(cast wallet decrypt-keystore deployer)
```

### Option C — Import from MetaMask seed phrase

If you exported a **12/24-word mnemonic** (testnet-only wallet):

```bash
cast wallet import deployer --mnemonic-path "m/44'/60'/0'/0/0" --interactive
# Paste mnemonic at prompt; set password
cast wallet address --account deployer
```

MetaMask default first account uses path `m/44'/60'/0'/0/0`.

### Option D — Import raw hex non-interactively

```bash
cast wallet import deployer --private-key 0xYOUR_KEY
# Prefer --interactive on shared machines
```

### Sanity checks

```bash
# Balances (fund if zero)
cast balance $(cast wallet address --account deployer) --rpc-url $SEPOLIA_RPC
cast balance $(cast wallet address --account deployer) --rpc-url $ARBITRUM_SEPOLIA_RPC
cast balance $(cast wallet address --account deployer) --rpc-url $BASE_SEPOLIA_RPC

# Optional treasury addresses (default to deployer if unset)
export PLATFORM_TREASURY=$(cast wallet address --account deployer)
export GAS_RESERVE=$(cast wallet address --account deployer)
```

---

## Step 2 — Create VRF subscriptions

Do this **once per chain** before deploying `LaneToken`.

1. Open [vrf.chain.link](https://vrf.chain.link)
2. Connect wallet → select network → **Create subscription**
3. Record subscription ID (uint256) for each chain:

| Chain | Env var usage |
|-------|---------------|
| Sepolia | `VRF_SUBSCRIPTION_ID` when `DEPLOY_CHAIN=sepolia` |
| Arbitrum Sepolia | new ID when `DEPLOY_CHAIN=arbitrum-sepolia` |
| Base Sepolia | new ID when `DEPLOY_CHAIN=base-sepolia` |

You will add each deployed `LaneToken` as a consumer and fund with LINK **after** Phase 1 deploy.

---

## Step 3 — Phase 1: Deploy contracts (each chain)

From repo root:

```bash
cd contracts
set -a && source .env && set +a
# Keystore path (no PRIVATE_KEY):
export DEPLOYER=$(cast wallet address --account laneDeployer)
# Or: export PRIVATE_KEY=...   if using Option A
```

### 3a — Ethereum Sepolia

```bash
export DEPLOY_CHAIN=sepolia
export VRF_SUBSCRIPTION_ID=<your-sepolia-sub-id>

forge script script/DeployAll.s.sol:DeployAll \
  --rpc-url $SEPOLIA_RPC \
  --account laneDeployer \
  --sender $DEPLOYER \
  --broadcast \
  --verify \
  -vvvv
```

Save console output addresses:

- `LaneToken`
- `LaneController`
- `LaneExecutor`

### 3b — Arbitrum Sepolia

```bash
export DEPLOY_CHAIN=arbitrum-sepolia
export VRF_SUBSCRIPTION_ID=<your-arb-sepolia-sub-id>

forge script script/DeployAll.s.sol:DeployAll \
  --rpc-url $ARBITRUM_SEPOLIA_RPC \
  --account laneDeployer \
  --sender $DEPLOYER \
  --broadcast \
  --verify \
  -vvvv
```

### 3c — Base Sepolia

```bash
export DEPLOY_CHAIN=base-sepolia
export VRF_SUBSCRIPTION_ID=<your-base-sepolia-sub-id>

forge script script/DeployAll.s.sol:DeployAll \
  --rpc-url $BASE_SEPOLIA_RPC \
  --account laneDeployer \
  --sender $DEPLOYER \
  --broadcast \
  --verify \
  --slow \
  -vvvv
```

If broadcast fails with `gapped-nonce tx from delegated accounts`, check `cast nonce $DEPLOYER --rpc-url $BASE_SEPOLIA_RPC` and retry with `--resume` (Forge saves partial txs under `contracts/broadcast/DeployAll.s.sol/84532/`).

### 3d — Post-deploy per chain

For **each** chain’s `LaneToken` and `LaneExecutor` (live addresses in [DEPLOY_TESTNET.md](./DEPLOY_TESTNET.md)):

| Task | How |
|------|-----|
| VRF consumer | vrf.chain.link → subscription → Add consumer → `LaneToken` address |
| Fund VRF sub | Add **5–10 LINK** to subscription |
| Fund `LaneToken` CCIP | `cast send <LANE_TOKEN> --value 0.02ether --rpc-url $RPC --account laneDeployer` |
| Fund `LaneExecutor` CCIP | `cast send <LANE_EXECUTOR> --value 0.05ether --rpc-url $SEPOLIA_RPC --account laneDeployer` (0.02 on L2s) |
| Record addresses | `contracts/deployments/testnet.json` (already filled) |

Example balance check:

```bash
cast balance $LANE_EXECUTOR --rpc-url $SEPOLIA_RPC
```

### 3e — Tune `minBet` (recommended)

Default `minBet` is `1e6` wei of LINK (tiny on 18-decimal LINK). As owner:

```bash
# Example: 0.1 LINK minimum bet
cast send 0xf7a6CAa15Fa51d30439e32E220A507F04611544a \
  "setMinBet(uint256)" 100000000000000000 \
  --rpc-url $SEPOLIA_RPC \
  --account laneDeployer
```

---

## Step 4 — Phase 2: Cross-chain peer wiring

After all three chains are deployed, run **wire-only** on each chain with peer addresses from your notes / `testnet.json`.

### 4a — Sepolia

```bash
export DEPLOY_CHAIN=sepolia
export WIRE_ONLY=true
export EXISTING_LANE_TOKEN=0x...        # Sepolia LaneToken
export EXISTING_LANE_CONTROLLER=0x...   # Sepolia LaneController
export EXISTING_LANE_EXECUTOR=0x...     # Sepolia LaneExecutor
export REMOTE_EXECUTOR_ARBITRUM_SEPOLIA=0x...
export REMOTE_EXECUTOR_BASE_SEPOLIA=0x...
export REMOTE_LANE_TOKEN_ARBITRUM_SEPOLIA=0x...
export REMOTE_LANE_TOKEN_BASE_SEPOLIA=0x...

forge script script/DeployAll.s.sol:DeployAll \
  --rpc-url $SEPOLIA_RPC \
  --account laneDeployer \
  --sender $DEPLOYER \
  --broadcast \
  -vvvv
```

### 4b — Arbitrum Sepolia

```bash
export DEPLOY_CHAIN=arbitrum-sepolia
export WIRE_ONLY=true
export EXISTING_LANE_TOKEN=0x...
export EXISTING_LANE_CONTROLLER=0x...
export EXISTING_LANE_EXECUTOR=0x...
export REMOTE_EXECUTOR_SEPOLIA=0x...
export REMOTE_EXECUTOR_BASE_SEPOLIA=0x...
export REMOTE_LANE_TOKEN_SEPOLIA=0x...
export REMOTE_LANE_TOKEN_BASE_SEPOLIA=0x...

forge script script/DeployAll.s.sol:DeployAll \
  --rpc-url $ARBITRUM_SEPOLIA_RPC \
  --account laneDeployer \
  --sender $DEPLOYER \
  --broadcast \
  -vvvv
```

### 4c — Base Sepolia

```bash
export DEPLOY_CHAIN=base-sepolia
export WIRE_ONLY=true
export EXISTING_LANE_TOKEN=0x...
export EXISTING_LANE_CONTROLLER=0x...
export EXISTING_LANE_EXECUTOR=0x...
export REMOTE_EXECUTOR_SEPOLIA=0x...
export REMOTE_EXECUTOR_ARBITRUM_SEPOLIA=0x...
export REMOTE_LANE_TOKEN_SEPOLIA=0x...
export REMOTE_LANE_TOKEN_ARBITRUM_SEPOLIA=0x...

forge script script/DeployAll.s.sol:DeployAll \
  --rpc-url $BASE_SEPOLIA_RPC \
  --account laneDeployer \
  --sender $DEPLOYER \
  --broadcast \
  -vvvv
```

### 4d — Verify wiring

On each chain:

```bash
# CRE forwarder matches ChainConfig
cast call $LANE_CONTROLLER "creForwarder()(address)" --rpc-url $SEPOLIA_RPC

# Hop recorder = local executor
cast call $LANE_CONTROLLER "hopRecorders(address)(bool)" $LANE_EXECUTOR --rpc-url $SEPOLIA_RPC

# Remote executor for Arbitrum selector on Sepolia executor
cast call $LANE_EXECUTOR \
  "remoteExecutors(uint64)(address)" 3478487238524512106 \
  --rpc-url $SEPOLIA_RPC
```

Update `contracts/deployments/testnet.json` with all contract addresses and `wiring.remoteExecutors` / `wiring.remoteLaneTokens`.

---

## Step 5 — CRE workflow configuration

```bash
cd cre/lane-checker-cre
cre login   # browser auth
```

Edit **staging** configs with your live addresses:

| Workflow | File | Key fields |
|----------|------|------------|
| round-scheduler | `round-scheduler/config.staging.json` | `laneControllerAddress` (Sepolia) |
| hop-sender | `hop-sender/config.staging.json` | per-chain copy: `laneExecutorAddress`, `isOriginChain: true` on Sepolia |
| hop-monitor | `hop-monitor/config.staging.json` | Sepolia controller + all chain RPCs |
| settlement | `settlement/config.staging.json` | Sepolia controller |
| sweep-unclaimed | `sweep-unclaimed/config.staging.json` | Sepolia controller |
| lane-benchmark | `lane-benchmark/config.staging.json` | HTTP only |

Simulate locally before DON deploy:

```bash
cre workflow simulate round-scheduler --target staging-settings
cre workflow simulate hop-sender --target staging-settings
cre workflow simulate settlement --target staging-settings
```

If contract ABIs changed:

```bash
./scripts/sync-cre-abis.sh
```

Deploy workflows to the testnet DON when ready (CRE dashboard / CLI per [CRE docs](https://docs.chain.link/cre)).

---

## Step 6 — First tests

### Test A — Solo game on Sepolia

Uses `LaneToken` + VRF + CCIP.

**6A.1 — Get LINK on Sepolia**

```bash
LINK=0x779877A7B0D9E8603169DdbD7836e478b4624789
PLAYER=$PRIVATE_KEY   # or a separate test wallet
```

**6A.2 — Approve + deposit**

```bash
# Approve 1 LINK
cast send $LINK \
  "approve(address,uint256)" $LANE_TOKEN 1000000000000000000 \
  --rpc-url $SEPOLIA_RPC \
  --private-key $PLAYER

# Deposit 0.5 LINK
cast send $LANE_TOKEN \
  "deposit(uint256)" 500000000000000000 \
  --rpc-url $SEPOLIA_RPC \
  --private-key $PLAYER
```

**6A.3 — Start game (3 hops, stake 0.1 LINK)**

`startGame` signature: `startGame(uint64 destSelector, uint256 amount, uint8 maxHops)`

For first hop destination, pass any wired selector (VRF may override on later hops). Example to Arbitrum:

```bash
cast send $LANE_TOKEN \
  "startGame(uint64,uint256,uint8)" \
  3478487238524512106 \
  100000000000000000 \
  3 \
  --rpc-url $SEPOLIA_RPC \
  --private-key $PLAYER \
  --gas-limit 800000
```

**6A.4 — Watch progress**

```bash
# Game count
cast call $LANE_TOKEN "gameCount()(uint256)" --rpc-url $SEPOLIA_RPC

# CCIP events on Etherscan / cast logs
# VRF fulfillment should arrive within ~1–3 blocks after hop needs randomness
```

**6A.5 — Withdraw after finish**

When `hopCount >= maxHops` and booked balance credited:

```bash
cast call $LANE_TOKEN "getBookedBalance(address)(uint256)" $PLAYER_ADDR --rpc-url $SEPOLIA_RPC

cast send $LANE_TOKEN \
  "withdraw(uint256)" 100000000000000000 \
  --rpc-url $SEPOLIA_RPC \
  --private-key $PLAYER
```

**Pass criteria:** CCIP `MessageSent` on origin; inbound hop on peer `LaneToken`; VRF callback if more hops remain; booked balance increases once globally per game.

---

### Test B — Parimutuel round on Sepolia

Uses `LaneController` + multi-chain `LaneExecutor` hops.

**6B.1 — Manual round (skip CRE scheduler for first test)**

As owner/deployer, create a round with two lane paths (each path = array of CCIP selectors):

```bash
CONTROLLER=$LANE_CONTROLLER

# createRound(uint8 laneCount, uint64[][] lanePaths, uint8 requiredHops)
# Paths from round-scheduler config.staging.json:
# Lane 0: Sepolia → Arbitrum → Base
# Lane 1: Sepolia → Base → Arbitrum
# requiredHops = 3

# Use cast calldata or a small forge script; example via cast (adjust encoding):
# Easiest path: wait for CRE round-scheduler CRON or run cre workflow simulate
```

Practical first test — **simulate CRE round creation**:

```bash
cd cre/lane-checker-cre
cre workflow simulate round-scheduler --target staging-settings
```

Or call from Foundry console / script as owner:

```solidity
uint64[] memory lane0 = new uint64[](3);
lane0[0] = 16015286601757825753;
lane0[1] = 3478487238524512106;
lane0[2] = 10344971235874465080;
// ... lane1 alternate path ...
controller.createRound(2, paths, 3);
```

**6B.2 — Place bets**

```bash
# Approve LINK to controller
cast send $LINK \
  "approve(address,uint256)" $CONTROLLER 1000000000000000000 \
  --rpc-url $SEPOLIA_RPC \
  --private-key $PLAYER

# buyLaneTokens(roundId, laneId, amount) — roundId usually 1 for first round
cast send $CONTROLLER \
  "buyLaneTokens(uint256,uint8,uint256)" 1 0 200000000000000000 \
  --rpc-url $SEPOLIA_RPC \
  --private-key $PLAYER
```

**6B.3 — Start race**

Owner or CRE:

```bash
cast send $CONTROLLER \
  "startRace(uint256)" 1 \
  --rpc-url $SEPOLIA_RPC \
  --private-key $PRIVATE_KEY
```

**6B.4 — Drive hops**

Run `hop-sender` simulation or wait for live CRE CRON. Each hop needs funded executors on the sending chain.

Monitor:

```bash
cast logs --from-block latest \
  --address $CONTROLLER \
  "HopCompleted(uint256,uint8,uint64,uint256,uint256)" \
  --rpc-url $SEPOLIA_RPC
```

**6B.5 — Settlement & claim**

After `WinnerDeclared` and `settlement` workflow (or manual):

```bash
cast send $CONTROLLER "distributePrizes(uint256)" 1 \
  --rpc-url $SEPOLIA_RPC \
  --private-key $PRIVATE_KEY

# Bettor claims
cast send $CONTROLLER \
  "claimPrize(uint256)" 1 \
  --rpc-url $SEPOLIA_RPC \
  --private-key $PLAYER
```

**Pass criteria:** `HopCompleted` events for both lanes; `WinnerDeclared`; `PrizesDistributed`; winner can `claimPrize` and LINK balance increases.

---

### Test C — Local regression (optional, no testnet spend)

```bash
cd contracts
forge test --match-contract FullSmoke -vv
forge test -vv   # full suite
```

---

## Step 7 — Frontend (optional demo)

```bash
cd frontend
cp .env.example .env.local
# Fill addresses from contracts/deployments/testnet.json

npm install
npm run dev
```

Open `http://localhost:3000`, connect wallet on Sepolia, approve LINK, try solo deposit or parimutuel bet UI.

---

## Step 8 — Update deployment manifest

Fill `contracts/deployments/testnet.json`:

```json
"contracts": {
  "LaneToken": "0x...",
  "LaneController": "0x...",
  "LaneExecutor": "0x..."
},
"wiring": {
  "hopRecorder": "0x...",
  "remoteExecutors": { "...": "0x..." },
  "remoteLaneTokens": { "...": "0x..." }
}
```

Set `"updatedAt"` to ISO timestamp. Commit **addresses only** — never keys.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `forge script` fails on `PRIVATE_KEY` | `export DEPLOYER=$(cast wallet address --account laneDeployer)` + `--account laneDeployer --sender $DEPLOYER` |
| `Failed to decode private key` | Use `cast wallet address --account laneDeployer`, not `cast wallet address laneDeployer` |
| `default sender` on broadcast | Set `--sender $DEPLOYER` (must match keystore address) |
| `gapped-nonce tx from delegated accounts` (Base) | Add `--slow`; retry with `--resume`; verify nonce with `cast nonce $DEPLOYER --rpc-url $BASE_SEPOLIA_RPC` |
| `UnknownDestination` on `sendHop` | Re-run Phase 2 wiring on **sending** chain executor |
| `UnauthorizedSource` on CCIP receive | Wrong `remoteExecutors` mapping |
| `NotAuthorized` on CRE write | `creForwarder` not set on controller/executor |
| `recordHop` reverts | `setHopRecorder(executor)` missing; wrong `hopChainSelector` |
| CCIP send reverts (fee) | Fund executor with more native ETH |
| VRF never fires | Add `LaneToken` as consumer; fund LINK on subscription |
| `buyLaneTokens` reverts | Approve LINK; bet ≥ `minBet`; round in Betting state |
| `getRoundWinner` confusing | Returns `255` when unset, not `0` |

---

## Quick reference — env vars

| Variable | Required | Description |
|----------|----------|-------------|
| `DEPLOYER` | Keystore path | `cast wallet address --account laneDeployer`; also pass to `--sender` |
| `KEYSTORE_ACCOUNT` | Keystore path | Foundry keystore name (default `laneDeployer`) |
| `PRIVATE_KEY` | Alt to keystore | Deployer hex key (omit when using keystore) |
| `SEPOLIA_RPC` | Yes | Sepolia JSON-RPC |
| `ARBITRUM_SEPOLIA_RPC` | Yes | Arbitrum Sepolia RPC |
| `BASE_SEPOLIA_RPC` | Yes | Base Sepolia RPC |
| `DEPLOY_CHAIN` | Yes | `sepolia` \| `arbitrum-sepolia` \| `base-sepolia` |
| `VRF_SUBSCRIPTION_ID` | Phase 1 deploy | Per-chain VRF sub |
| `PLATFORM_TREASURY` | No | Defaults to deployer |
| `GAS_RESERVE` | No | Defaults to deployer |
| `WIRE_ONLY` | Phase 2 | `true` + `EXISTING_LANE_*` |
| `REMOTE_EXECUTOR_*` | Phase 2 | Peer executor addresses |
| `REMOTE_LANE_TOKEN_*` | Phase 2 | Peer LaneToken addresses |

---

## Related docs

- [GAME_SYSTEM.md](./GAME_SYSTEM.md) — full game & architecture
- [DEPLOY_TESTNET.md](./DEPLOY_TESTNET.md) — checklist summary
- [PRE_DEPLOY_RUNBOOK.md](./PRE_DEPLOY_RUNBOOK.md) — funding & monitoring
- [IMPLEMENTATION.md](./IMPLEMENTATION.md) — roadmap exit criteria
