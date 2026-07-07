# DeployAll Dry-Run Results

Dry-runs executed with `forge script` (no `--broadcast`) against public RPCs.

## RPC endpoints

| Chain | URL |
|-------|-----|
| Ethereum Sepolia | `https://ethereum-sepolia-rpc.publicnode.com` |
| Arbitrum Sepolia | `https://arbitrum-sepolia-rpc.publicnode.com` |
| Base Sepolia | `https://base-sepolia-rpc.publicnode.com` |

## Results

| Chain | Script | On-chain sim | Gas | Est. cost |
|-------|--------|--------------|-----|-----------|
| Sepolia | PASS | PASS | ~7,188,459 | ~0.0156 ETH |
| Arbitrum Sepolia | PASS | PASS | ~7,580,202 | ~0.00031 ETH |
| Base Sepolia | PASS | FAIL (0 ETH deployer) | — | — |

All three chains complete script logic without Solidity reverts. Phase 1 peer skips are expected (no `REMOTE_*` env vars).

**Base Sepolia** on-chain simulation fails with `lack of funds (0) for max fee` when the deployer has no testnet ETH. Use a funded key before broadcast, or `--skip-simulation` for unsigned tx artifacts only.

## Command template

```bash
cd contracts
export DEPLOY_CHAIN=sepolia          # arbitrum-sepolia | base-sepolia
export VRF_SUBSCRIPTION_ID=1          # replace with real sub ID
export PRIVATE_KEY=0x...              # funded deployer — never commit
export PLATFORM_TREASURY=0x...
export GAS_RESERVE=0x...

forge script script/DeployAll.s.sol:DeployAll \
  --rpc-url $SEPOLIA_RPC \
  -vvv
```

## Broadcast blockers

1. Fund deployer with testnet ETH on all three chains
2. Create and fund VRF v2.5 subscriptions per chain
3. Phase 2 peer wiring (`WIRE_ONLY=true`, `REMOTE_*` env vars)
4. Fund LaneExecutor contracts with native token for CCIP fees
5. Fund LaneToken with native token for solo CCIP fee path

See `docs/DEPLOY_TESTNET.md` for the full checklist.
