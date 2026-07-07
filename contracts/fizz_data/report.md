# Fizz Report — CCIP Lane Checker

**Generated:** 2026-07-07  
**Mode:** automatic  
**Project:** `contracts/`

## Summary

Stateful fuzz harness generated under `test/fizz/` with Medusa/Echidna configs at project root. Primary targets: **LaneController** (parimutuel) and **LaneToken** (solo CCIP+VRF).

## Artifacts

| Path | Purpose |
|------|---------|
| `test/fizz/FuzzTester.sol` | Medusa/Echidna entry point |
| `test/fizz/FoundryTester.sol` | Foundry debug + lifecycle smoke |
| `test/fizz/handlers/` | Clamped/unclamped action handlers |
| `PROPERTIES.md` | Property spec (GL-01..04, SP-01..02) |
| `fizz_data/` | ABIs, selection, corpus, coverage |
| `medusa.json` / `echidna.yaml` | Fuzzer configs |

## Properties (SHOULD-HOLD)

1. **GL-01** `property_controllerTokenSolvency` — controller balance covers lane pools + unclaimed prize shares
2. **GL-02** `property_laneTokenBookedSolvency` — underlying balance ≥ booked + in-play
3. **GL-03** `property_prizeShareConservation` — claims never exceed allocated shares
4. **GL-04** `property_distributedPayoutMatchesCalculator` — 70/15/10/5 split via `PrizeCalculator`

## Coverage (Medusa cycle 1)

| Contract | Hit |
|----------|-----|
| LaneController.sol | 85% |
| LaneToken.sol | 74% |
| PrizeCalculator.sol | 100% |

Full report: `fizz_data/corpus_medusa/coverage/coverage_report.html`

## Campaign Notes

Initial Medusa coverage run found **1 property violation** on `property_controllerTokenSolvency` when `sweepUnclaimed` ran without updating ghost claim trackers. Harness was patched to sync ghosts on sweep/distribute. Re-run recommended:

```bash
cd contracts
node ~/.claude/skills/fizz/scripts/run_medusa.js . --meta-dir fizz_data --timeout 600
```

Or Echidna:

```bash
cd contracts
echidna . --contract FuzzTester --config echidna.yaml
```

Foundry smoke:

```bash
cd contracts
forge test --match-contract FoundryTester -vv
```

## Gaps / TODO

- LaneExecutor not in harness (CCIP relay); add `MockCCIPRouter` hop injection handlers for cross-chain parimutuel
- Cross-chain solo return-hop (EX-01) needs bidirectional `MockDeliveringCCIPRouter` setup
- Run `/fizz-sync` after future `src/` changes to refresh handler stubs

## Cost Estimate

See `fizz_data/cost-estimate.md` (~$3.55 ballpark for full agent-driven invariant discovery; this run used inline property authoring).
