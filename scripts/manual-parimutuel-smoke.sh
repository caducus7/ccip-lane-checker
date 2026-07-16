#!/usr/bin/env bash
# Owner-operated parimutuel smoke test (no CRE DON required).
# Automates createRound → optional bets → startRace → CCIP hop loop → settle → claim.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONTRACTS="$ROOT/contracts"
SCRIPT="script/ManualParimutuelSmoke.s.sol:ManualParimutuelSmoke"

# Defaults from contracts/deployments/testnet.json (Sepolia home chain).
export LANE_CONTROLLER="${LANE_CONTROLLER:-0xf7a6CAa15Fa51d30439e32E220A507F04611544a}"
export LINK_TOKEN="${LINK_TOKEN:-0x779877A7B0D9E8603169DdbD7836e478b4624789}"
export LANE_EXECUTOR_SEPOLIA="${LANE_EXECUTOR_SEPOLIA:-0xbd8b72eB19Fea6e25597F40a63Ea1DeF3C600990}"
export LANE_EXECUTOR_ARBITRUM_SEPOLIA="${LANE_EXECUTOR_ARBITRUM_SEPOLIA:-0xa159214985Bbb3f7e7A0F986C723262914150ac7}"
export LANE_EXECUTOR_BASE_SEPOLIA="${LANE_EXECUTOR_BASE_SEPOLIA:-0xf2682e839FD4aC8bA60081710ce8689CCcc7e803}"

CCIP_WAIT_SEC="${CCIP_WAIT_SEC:-60}"
MAX_DRIVE_ROUNDS="${MAX_DRIVE_ROUNDS:-40}"
SKIP_BETS="${SKIP_BETS:-0}"
BET_AMOUNT="${BET_AMOUNT:-200000000000000000}" # 0.2 LINK (18 decimals)

usage() {
  cat <<'EOF'
Usage: ./scripts/manual-parimutuel-smoke.sh <command>

Commands:
  env           Print resolved addresses and env (source contracts/.env first)
  status        Read round + lane state (no broadcast)
  setup         createRound on Sepolia
  bet           Place deployer bets on both lanes (SKIP_BETS=1 to skip in run-all)
  start         startRace on Sepolia
  hops          send-next-hops once on sepolia, arbitrum-sepolia, base-sepolia
  drive         Loop hops until round Finished or MAX_DRIVE_ROUNDS exhausted
  settle        distributePrizes when round is Finished
  claim         claimPrize for deployer when Settled
  run-all       setup → bet → start → drive → settle → claim

Environment (from contracts/.env):
  SEPOLIA_RPC, ARBITRUM_SEPOLIA_RPC, BASE_SEPOLIA_RPC
  DEPLOYER or PRIVATE_KEY
  ROUND_ID          Target round (default: currentRoundId)
  SKIP_BETS=1       Skip betting in run-all
  CCIP_WAIT_SEC=60  Sleep between drive loops
  MAX_DRIVE_ROUNDS=40

Forge keystore:
  export DEPLOYER=$(cast wallet address --account laneDeployer)
  Uses --account laneDeployer --sender $DEPLOYER unless PRIVATE_KEY is set.
EOF
}

require_env() {
  if [[ -f "$CONTRACTS/.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "$CONTRACTS/.env"
    set +a
  fi
  : "${SEPOLIA_RPC:?Set SEPOLIA_RPC in contracts/.env}"
  : "${ARBITRUM_SEPOLIA_RPC:?Set ARBITRUM_SEPOLIA_RPC in contracts/.env}"
  : "${BASE_SEPOLIA_RPC:?Set BASE_SEPOLIA_RPC in contracts/.env}"

  if [[ -z "${DEPLOYER:-}" && -z "${PRIVATE_KEY:-}" ]]; then
    export DEPLOYER
    DEPLOYER="$(cast wallet address --account laneDeployer)"
  fi
}

forge_args() {
  if [[ -n "${PRIVATE_KEY:-}" ]]; then
    echo ""
  else
    echo "--account laneDeployer --sender ${DEPLOYER}"
  fi
}

run_smoke() {
  local rpc="$1"
  local action="$2"
  local extra_env=("${@:3}")
  (
    cd "$CONTRACTS"
    SMOKE_ACTION="$action" "${extra_env[@]}" \
      forge script "$SCRIPT" \
        --rpc-url "$rpc" \
        $(forge_args) \
        --broadcast \
        -vvv
  )
}

run_status() {
  (
    cd "$CONTRACTS"
    SMOKE_ACTION=status forge script "$SCRIPT" --rpc-url "$SEPOLIA_RPC" -vv
  )
}

cmd_hops() {
  run_smoke "$SEPOLIA_RPC" send-next-hops SMOKE_CHAIN=sepolia
  run_smoke "$ARBITRUM_SEPOLIA_RPC" send-next-hops SMOKE_CHAIN=arbitrum-sepolia
  run_smoke "$BASE_SEPOLIA_RPC" send-next-hops SMOKE_CHAIN=base-sepolia
}

round_state() {
  local rid="${ROUND_ID:-}"
  if [[ -z "$rid" ]]; then
    rid="$(cast call "$LANE_CONTROLLER" "currentRoundId()(uint256)" --rpc-url "$SEPOLIA_RPC")"
  fi
  cast call "$LANE_CONTROLLER" "getRoundState(uint256)(uint8)" "$rid" \
    --rpc-url "$SEPOLIA_RPC" 2>/dev/null || echo "255"
}

cmd_drive() {
  echo "==> Driving hops (CCIP_WAIT_SEC=$CCIP_WAIT_SEC, max rounds=$MAX_DRIVE_ROUNDS)"
  for ((i = 1; i <= MAX_DRIVE_ROUNDS; i++)); do
    echo "--- drive iteration $i ---"
    run_status || true
    state="$(round_state)"
    echo "Round state: $state (2=Finished, 3=Settled)"
    if [[ "$state" == "2" || "$state" == "3" ]]; then
      echo "Round complete."
      return 0
    fi
    cmd_hops || true
    sleep "$CCIP_WAIT_SEC"
  done
  echo "WARNING: MAX_DRIVE_ROUNDS reached; check status and run drive again." >&2
  return 1
}

cmd_run_all() {
  run_smoke "$SEPOLIA_RPC" setup
  if [[ "$SKIP_BETS" != "1" ]]; then
    run_smoke "$SEPOLIA_RPC" bet BET_LANE=0
    run_smoke "$SEPOLIA_RPC" bet BET_LANE=1
  else
    echo "==> Skipping bets (SKIP_BETS=1)"
  fi
  run_smoke "$SEPOLIA_RPC" start
  cmd_drive
  run_smoke "$SEPOLIA_RPC" settle
  run_smoke "$SEPOLIA_RPC" claim
  echo "==> run-all complete"
  run_status
}

cmd_env() {
  echo "LANE_CONTROLLER=$LANE_CONTROLLER"
  echo "LINK_TOKEN=$LINK_TOKEN"
  echo "LANE_EXECUTOR_SEPOLIA=$LANE_EXECUTOR_SEPOLIA"
  echo "LANE_EXECUTOR_ARBITRUM_SEPOLIA=$LANE_EXECUTOR_ARBITRUM_SEPOLIA"
  echo "LANE_EXECUTOR_BASE_SEPOLIA=$LANE_EXECUTOR_BASE_SEPOLIA"
  echo "DEPLOYER=${DEPLOYER:-}"
  echo "ROUND_ID=${ROUND_ID:-<current>}"
}

main() {
  require_env
  local cmd="${1:-}"
  case "$cmd" in
    env) cmd_env ;;
    status) run_status ;;
    setup) run_smoke "$SEPOLIA_RPC" setup ;;
    bet)
      lane="${2:-0}"
      run_smoke "$SEPOLIA_RPC" bet BET_LANE="$lane" BET_AMOUNT="$BET_AMOUNT"
      ;;
    start) run_smoke "$SEPOLIA_RPC" start ;;
    hops) cmd_hops ;;
    drive) cmd_drive ;;
    settle) run_smoke "$SEPOLIA_RPC" settle ;;
    claim) run_smoke "$SEPOLIA_RPC" claim ;;
    run-all) cmd_run_all ;;
    -h|--help|help|"") usage ;;
    *) echo "Unknown command: $cmd" >&2; usage; exit 1 ;;
  esac
}

main "$@"
