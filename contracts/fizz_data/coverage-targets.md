# Coverage Targets

Fuzz profile: Medusa on `FuzzTester` with `coverageEnabled: true`.

| Contract | Role | Target | Typical hit (post harness v2) | Status |
|---|---|---|---|---|
| LaneController | Core protocol | 90%+ | ~92% | on track |
| LaneToken | Core protocol | 90%+ | ~91% | on track |
| LaneExecutor | Core protocol | 95%+ | ~97% | on track |
| CreReportAuth | Library | 100% | 100% | met |
| PrizeCalculator | Library | inherited | 100% | skip |

## Notes

- **Source line coverage ≠ executable coverage.** Struct fields, state declarations, immutables, and error declarations count as lines in `lcov` but are not runtime branches.
- **`coverage_runAll(uint256)`** in `CoverageHandlers.sol` is the primary entry for path completion; constructor `_seedCoverage()` warms state at deploy.
- **Spoke executor** (`spokeExecutor` in `Base.sol`) exercises `LaneExecutor._relayHopToHome`.
- **Dual-share claim** (`coverage_controller_dualShareClaim`) hits `_consumeDualShareClaim` when winner payout redirects to the runner-up lane.

## Run

```bash
cd contracts
forge build --build-info
medusa fuzz --config medusa.json
# report: fizz_data/corpus_medusa/coverage/coverage_report.html
```

## Remaining gaps (expected)

| Area | Why hard to hit | Covered by |
|------|-----------------|------------|
| `LaneController` constructor `ZeroAddress` | Only at deploy | `test/audit/CoverageNegatives.t.sol` |
| `LaneToken` `BridgeCustodyMismatch` | Needs faulty router mock | `CoverageNegatives.t.sol` (`MockNoPullCCIPRouter`) |
| `LaneToken` duplicate `foreignKey` finish | Multi-chain race timing | `CoverageNegatives.t.sol` + `FifthPassFixes.t.sol` |
| Revert-only modifier / CRE auth paths | Invalid callers | `CoverageNegatives.t.sol` |

Run the negative suite:

```bash
forge test --match-contract CoverageNegativesTest
```
