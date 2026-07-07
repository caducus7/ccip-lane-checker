# CCIP Lane Checker — Protocol Understanding (Fizz)

## Overview

Cross-chain latency racing protocol with two modes:
1. **Parimutuel (LaneController + LaneExecutor)** — bettors buy lane tokens; CRE/executors record CCIP hops; first finisher wins 70%, runner-up 30%.
2. **Solo (LaneToken)** — single-player stake bridged across chains via CCIP; VRF picks next chain; game ends after maxHops.

## Deployment Order

1. MockERC20 (betting token) or CCIP BnM for solo
2. LaneController(owner, token, treasury, gasReserve, creForwarder)
3. LaneExecutor(router, owner) — setHomeConfig, setLaneController, setRemoteExecutor, setHopSender
4. LaneToken(router, underlying, vrfCoordinator, subId, gasLane, chainId, localSelector, supportedChains) — setRemoteLaneToken per peer

## Roles

| Actor | Permissions |
|-------|-------------|
| Owner | pause, config setters, hopRecorder grants |
| CRE forwarder | createRound, startRace, distributePrizes, sweepUnclaimed, onReport |
| Hop recorder (executor) | recordHop on controller |
| Hop sender | sendHop on executor |
| Players | buyLaneTokens, claimPrize / deposit, withdraw, startGame, abandonGame |

## Candidate Invariants

### LaneController
- Token conservation: `token.balanceOf(controller) >= sum(unclaimed winner+runnerUp shares) + unclaimed bettor refunds`
- `totalPrizePool` matches sum of lane stakes after race start
- No double-claim per (round, bettor)
- State machine: Created → Racing → Finished → Settled; no backward transitions
- First finisher is winner; runner-up only after all lanes finish or timeout
- `claimedWinner + claimedRunnerUp <= winnerShare + runnerUpShare` per round

### LaneToken
- `s_tokensInPlay + s_totalBooked + sum(s_balances)` reconciles with underlying balance on chain
- Active game amount counted in `s_tokensInPlay` unless bridged out
- Game finishes exactly at `hopCount == maxHops`
- Duplicate CCIP messageIds rejected

## Fuzz Harness Strategy

- **Primary target:** LaneController parimutuel lifecycle (mock token, mock executor as hopRecorder). Avoid full CCIP simulator in fuzz loop — call `recordHop` directly as trusted executor.
- **Secondary:** LaneToken deposit/withdraw/startGame with MockDeliveringCCIPRouter + MockVRF for solo paths.
- LaneExecutor `sendHop` optional; CCIP receive paths exercised via mock router in dedicated handlers.

## External Dependencies (mock)

- IERC20: MockERC20
- CCIP router: MockCCIPRouter or MockDeliveringCCIPRouter
- VRF: MockVRFCoordinatorV2Plus
