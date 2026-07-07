# CCIP Lane Checker

Gamified CCIP lane benchmarking: race tokens across chains, bet on lanes, and measure real cross-chain latency.

## Monorepo

| Package | Purpose |
|---------|---------|
| `contracts/` | Foundry — on-chain game logic, CCIP hops, VRF randomness |
| `cre/` | CRE workflows — round orchestration, monitoring, settlement |
| `frontend/` | Next.js — race UI, betting, live lane status |
| `docs/` | Architecture and implementation steps |

## Game Modes

1. **Solo Challenge** (`LaneToken`) — one player races tokens across CCIP hops; lowest latency wins leaderboard rank.
2. **Parimutuel Race** (`LaneController`) — multiple players bet on lanes; first lane to complete its circuit wins the pool.

## Stack

- **CCIP** (current v1.6.x) — cross-chain token hops and messaging
- **VRF v2.5** — on-chain verifiable hop randomness (player-fair)
- **CRE** — replaces deprecated Automation/Functions for scheduling, monitoring, settlement
- **Chainlink Local** — local multi-chain simulation

> CCIP vNext is not yet public. Router interactions are isolated behind `IRouterClient` so migration is a config swap when available.

## Quick Start

```bash
cd contracts && forge test
for wf in round-scheduler hop-sender hop-monitor settlement lane-benchmark; do
  (cd cre/lane-checker-cre/$wf && bun install && bun run typecheck)
done
```

See [docs/IMPLEMENTATION.md](docs/IMPLEMENTATION.md) for the full step-by-step build plan.

## License

This repository is **source available**, not open source in the permissive sense.

- **Evaluation & development** — allowed under [LICENSE](LICENSE) (testnets, private networks, learning, contributions).
- **Commercial production use** — requires a separate commercial license from the author. If you want to deploy, white-label, or sell this product, [open an issue or contact caducus7 on GitHub](https://github.com/caducus7).

Third-party dependencies (`contracts/lib/`, npm packages) remain under their own licenses.

## Legacy

Migrated from `/home/caducus/lane-checker` (WIP, June 2025).
