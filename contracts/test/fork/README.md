# Testnet fork tests

Fork-based smoke tests against live testnets (`TestnetFork.t.sol`). Unlike the
Chainlink Local suites in `test/integration/`, these tests fork real networks over
RPC and verify that:

1. **Infra is live** — the canonical Chainlink addresses baked into
   `src/libraries/ChainConfig.sol` (CCIP router, LINK token, VRF coordinator) exist
   on-chain and the router supports the lanes to the other two testnets.
2. **Deployment is wired** *(post-deploy placeholder)* — once you deploy via
   `script/DeployAll.s.sol` and export the contract-address env vars below, the
   tests verify router wiring, remote peers, and controller/executor linkage.

## Skip behavior (CI-safe)

Every test calls `vm.skip(...)` when its RPC env var is unset, so a plain
`forge test --root contracts` **passes with these tests skipped** — no RPC access
or secrets are needed in CI.

## Running against live testnets

Set the RPC URLs (these also feed `[rpc_endpoints]` in `foundry.toml`):

```bash
export SEPOLIA_RPC="https://ethereum-sepolia-rpc.publicnode.com"       # or Alchemy/Infura
export ARBITRUM_SEPOLIA_RPC="https://sepolia-rollup.arbitrum.io/rpc"
export BASE_SEPOLIA_RPC="https://sepolia.base.org"

forge test --match-path "test/fork/*"
```

You can also run a single chain (only that chain's tests unskip):

```bash
SEPOLIA_RPC=... forge test --match-contract SepoliaForkTest -vv
```

## Post-deploy deployment checks

The `*_DeploymentWired` tests are scaffolds: they are no-ops until you point them
at deployed contracts. After running the deploy scripts and filling in
`deployments/testnet.json`, export the same addresses as env vars:

```bash
# Ethereum Sepolia
export LANE_TOKEN_SEPOLIA=0x...
export LANE_CONTROLLER_SEPOLIA=0x...
export LANE_EXECUTOR_SEPOLIA=0x...

# Arbitrum Sepolia
export LANE_TOKEN_ARBITRUM_SEPOLIA=0x...
export LANE_CONTROLLER_ARBITRUM_SEPOLIA=0x...
export LANE_EXECUTOR_ARBITRUM_SEPOLIA=0x...

# Base Sepolia
export LANE_TOKEN_BASE_SEPOLIA=0x...
export LANE_CONTROLLER_BASE_SEPOLIA=0x...
export LANE_EXECUTOR_BASE_SEPOLIA=0x...

forge test --match-path "test/fork/*" -vv
```

Any address left unset is simply not checked, so you can verify chains
incrementally as you deploy. Extend `_assertDeployment` in `TestnetFork.t.sol`
with more invariants (VRF subscription funding, gas balances, live hop sends)
as the deployment matures.
