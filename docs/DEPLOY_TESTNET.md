# Testnet Deployment Checklist

Step-by-step guide for deploying CCIP Lane Checker on Ethereum Sepolia, Arbitrum Sepolia, and Base Sepolia.

**Do not commit private keys.** Use a deployer wallet with testnet ETH on all three chains.

---

## Prerequisites

- [ ] Foundry installed (`forge`, `cast`)
- [ ] RPC URLs for Sepolia, Arbitrum Sepolia, Base Sepolia
- [ ] Deployer `PRIVATE_KEY` exported (never commit)
- [ ] VRF v2.5 subscription created **per chain** ([vrf.chain.link](https://vrf.chain.link))
- [ ] CCIP lanes enabled between the three testnets ([ccip.chain.link](https://ccip.chain.link))
- [ ] CRE CLI installed (`cre login` for workflow deploy later)

Canonical infra + CRE forwarder addresses live in `contracts/deployments/testnet.json` and `contracts/src/libraries/ChainConfig.sol`.

| Network | Chain ID | CCIP Selector | CRE Forwarder |
|---------|----------|---------------|---------------|
| Ethereum Sepolia | 11155111 | `16015286601757825753` | `0xF8344CFd5c43616a4366C34E3EEE75af79a74482` |
| Arbitrum Sepolia | 421614 | `3478487238524512106` | `0x76c9cf548b4179F8901cda1f8623568b58215E62` |
| Base Sepolia | 84532 | `10344971235874465080` | `0xF8344CFd5c43616a4366C34E3EEE75af79a74482` |

Verify forwarder addresses before mainnet-adjacent deploys: [CRE forwarder directory](https://docs.chain.link/cre/guides/workflow/using-evm-client/forwarder-directory-ts).

---

## Phase 1 — Deploy contracts (each chain)

Run once per chain. Peer wiring is skipped until `REMOTE_*` env vars are set.

```bash
cd contracts

export PRIVATE_KEY=0x...          # deployer
export PLATFORM_TREASURY=0x...      # optional; defaults to deployer
export GAS_RESERVE=0x...            # optional; defaults to deployer
```

### Ethereum Sepolia

```bash
export DEPLOY_CHAIN=sepolia
export VRF_SUBSCRIPTION_ID=<your-sepolia-sub-id>

forge script script/DeployAll.s.sol:DeployAll \
  --rpc-url $SEPOLIA_RPC \
  --broadcast \
  --verify \
  -vvvv
```

### Arbitrum Sepolia

```bash
export DEPLOY_CHAIN=arbitrum-sepolia
export VRF_SUBSCRIPTION_ID=<your-arb-sepolia-sub-id>

forge script script/DeployAll.s.sol:DeployAll \
  --rpc-url $ARB_SEPOLIA_RPC \
  --broadcast \
  --verify \
  -vvvv
```

### Base Sepolia

```bash
export DEPLOY_CHAIN=base-sepolia
export VRF_SUBSCRIPTION_ID=<your-base-sepolia-sub-id>

forge script script/DeployAll.s.sol:DeployAll \
  --rpc-url $BASE_SEPOLIA_RPC \
  --broadcast \
  --verify \
  -vvvv
```

### After each deploy

- [ ] Record `LaneToken`, `LaneController`, `LaneExecutor` in `contracts/deployments/testnet.json`
- [ ] Set `hopRecorder` in `wiring` to the local `LaneExecutor` address
- [ ] Add `LaneToken` as VRF consumer on the subscription
- [ ] Fund VRF subscription with LINK
- [ ] Fund `LaneExecutor` with native token for CCIP fees (~0.05 ETH per chain to start)

---

## Phase 2 — Cross-chain peer wiring

After all three chains are deployed, wire `remoteExecutors` and `remoteLaneTokens` on each chain.

Set peer addresses from `testnet.json`, then run **wire-only** mode (no redeploy):

### Ethereum Sepolia

```bash
export DEPLOY_CHAIN=sepolia
export WIRE_ONLY=true
export EXISTING_LANE_TOKEN=0x...
export EXISTING_LANE_CONTROLLER=0x...
export EXISTING_LANE_EXECUTOR=0x...
export REMOTE_EXECUTOR_ARBITRUM_SEPOLIA=0x...
export REMOTE_EXECUTOR_BASE_SEPOLIA=0x...
export REMOTE_LANE_TOKEN_ARBITRUM_SEPOLIA=0x...
export REMOTE_LANE_TOKEN_BASE_SEPOLIA=0x...

forge script script/DeployAll.s.sol:DeployAll \
  --rpc-url $SEPOLIA_RPC \
  --broadcast \
  -vvvv
```

### Arbitrum Sepolia

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
  --rpc-url $ARB_SEPOLIA_RPC \
  --broadcast \
  -vvvv
```

### Base Sepolia

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
  --broadcast \
  -vvvv
```

### Wiring checklist (per chain)

- [ ] `LaneController.creForwarder` = network KeystoneForwarder
- [ ] `LaneExecutor.creForwarder` = network KeystoneForwarder
- [ ] `LaneExecutor.hopSenders(creForwarder)` = `true`
- [ ] `LaneController.hopRecorders(executor)` = `true`
- [ ] `LaneExecutor.remoteExecutors(peerSelector)` set for each peer chain
- [ ] `LaneToken.remoteLaneTokens(peerSelector)` set for each peer chain
- [ ] Update `wiring.remoteExecutors` / `wiring.remoteLaneTokens` in `testnet.json`

---

## Phase 3 — CRE workflows

- [ ] Update `config.staging.json` in each workflow under `cre/lane-checker-cre/`:
  - `round-scheduler` — Sepolia `laneControllerAddress`
  - `hop-sender` — per-chain `laneExecutorAddress` (+ `isOriginChain` on Sepolia)
  - `hop-monitor` — Sepolia `laneControllerAddress`, all three chains in `chains`
  - `settlement` — Sepolia `laneControllerAddress`
  - `lane-benchmark` — no contract addresses (HTTP only)
- [ ] Simulate locally: `cre workflow simulate <workflow> --target staging-settings`
- [ ] Deploy workflows to testnet DON (after contracts wired)
- [ ] Run `./scripts/sync-cre-abis.sh` if contract ABIs changed

---

## Phase 4 — Smoke test

- [ ] Solo: `LaneToken.deposit` → `startGame` on Sepolia; confirm CCIP hop + VRF callback
- [ ] Parimutuel: wait for `round-scheduler` CRON or manually `createRound` + `startRace`
- [ ] Confirm `HopCompleted` / `LaneFinished` on controller (Sepolia is canonical controller chain)
- [ ] Confirm `WinnerDeclared` → `settlement` → `distributePrizes`
- [ ] Bettors call `claimPrize(roundId)`
- [ ] Frontend pointed at `testnet.json` addresses

---

## Dry run (no broadcast)

Simulate deploy without sending transactions:

```bash
cd contracts
DEPLOY_CHAIN=sepolia VRF_SUBSCRIPTION_ID=1 PRIVATE_KEY=1 \
  forge script script/DeployAll.s.sol:DeployAll --rpc-url $SEPOLIA_RPC
```

---

## Environment reference

| Variable | Required | Description |
|----------|----------|-------------|
| `PRIVATE_KEY` | Yes | Deployer wallet |
| `DEPLOY_CHAIN` | Yes | `sepolia`, `arbitrum-sepolia`, or `base-sepolia` |
| `VRF_SUBSCRIPTION_ID` | Deploy only | VRF v2.5 subscription (uint256) |
| `PLATFORM_TREASURY` | No | Defaults to deployer |
| `GAS_RESERVE` | No | Defaults to deployer |
| `CRE_FORWARDER` | No | Overrides ChainConfig default |
| `WIRE_ONLY` | Phase 2 | `true` to skip deploy, wire existing contracts |
| `EXISTING_LANE_*` | With `WIRE_ONLY` | Already-deployed addresses |
| `REMOTE_EXECUTOR_*` | Phase 2 | Peer executor per chain |
| `REMOTE_LANE_TOKEN_*` | Phase 2 | Peer LaneToken per chain |
| `WIRE_SELF` | No | Map local selector to self (simulator / single-chain) |

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `UnknownDestination` on `sendHop` | Re-run Phase 2 peer wiring for origin chain executor |
| `UnauthorizedSource` on CCIP receive | Mismatched `remoteExecutors` — source chain must point to correct dest executor |
| CRE write reverts `NotAuthorized` | `creForwarder` not set on controller/executor |
| `recordHop` reverts `NotAuthorized` | `setHopRecorder(executor)` missing on controller |
| CCIP send fails (insufficient fee) | Fund executor with more native token |
| VRF callback never fires | Add LaneToken as consumer; fund LINK on subscription |
