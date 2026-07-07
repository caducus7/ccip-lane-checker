# Fizz Properties — CCIP Lane Checker

## Global Properties (SHOULD-HOLD)

- [x] **GL-01** `property_controllerTokenSolvency` — Controller ERC20 balance covers outstanding lane pools and unclaimed prize shares. **Guarantee: SHOULD-HOLD** (fund safety).
- [x] **GL-02** `property_laneTokenBookedSolvency` — LaneToken on-chain underlying >= `s_totalBooked + s_tokensInPlay`. **Guarantee: SHOULD-HOLD** (withdraw solvency).
- [x] **GL-03** `property_prizeShareConservation` — Per settled round, cumulative claims never exceed allocated winner/runner-up shares. **Guarantee: SHOULD-HOLD**.
- [x] **GL-04** `property_distributedPayoutMatchesCalculator` — Settled round shares match `PrizeCalculator.calculate(pool)`. **Guarantee: SHOULD-HOLD** (70/15/10/5 split).
- [x] **GL-05** `property_originLaneTokenSolvency` / `property_remoteLaneTokenSolvency` — Cross-chain solo booked solvency per chain.
- [x] **GL-06** `property_allLaneTokensSolvent` — All LaneToken deployments solvent together.
- [x] **GL-07** `property_executorWired` — Executor remote routing and hopRecorder grant.

## Specific Properties

- [x] **SP-01** Buy lane tokens increases lane pool by exact deposit amount (inline in `controller_buyLaneTokens`).
- [x] **SP-02** Claim prize credits bettor balance by returned amount (inline in `controller_claimPrize`).
- [x] **SP-03** CCIP executor hop delivery increments hop count on controller (via `executor_sendHopAndDeliver`).

## Exploratory (future)

- [ ] **EX-01** Cross-chain solo game completes full maxHops circuit across origin and remote.
