#!/usr/bin/env bash
# Headless CRE validation for CI: sync ABIs, typecheck workflows, run unit tests,
# and optionally compile via `cre workflow simulate` when CRE auth is available.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CRE_ROOT="$ROOT/cre/lane-checker-cre"
CRE_BIN="${CRE_BIN:-cre}"

WORKFLOWS=(
  round-scheduler
  hop-sender
  hop-monitor
  settlement
  sweep-unclaimed
  lane-benchmark
)

echo "==> Syncing shared CRE ABIs"
"$ROOT/scripts/sync-cre-abis.sh"

echo "==> Verifying LaneController ABI alignment with forge build"
python3 - <<'PY'
import json
import re
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1] if False else Path(".")
root = Path.cwd()
forge_abi = json.loads(
    (root / "contracts/out/LaneController.sol/LaneController.json").read_text()
)["abi"]
forge_funcs = {item["name"] for item in forge_abi if item["type"] == "function"}

shared = (root / "cre/lane-checker-cre/shared/lane-controller-abi.ts").read_text()
shared_funcs = set(re.findall(r'"function (\w+)\(', shared))

required = {
    "createRound",
    "startRace",
    "declareWinner",
    "distributePrizes",
    "claimPrize",
    "sweepUnclaimed",
    "getRoundWinner",
    "getRoundState",
    "getLane",
    "currentRoundId",
}

missing = required - shared_funcs
unknown = shared_funcs - forge_funcs
if missing:
    print(f"Missing required functions in shared ABI: {sorted(missing)}", file=sys.stderr)
    sys.exit(1)
if unknown:
    print(f"Shared ABI references unknown forge functions: {sorted(unknown)}", file=sys.stderr)
    sys.exit(1)
print("LaneController shared ABI matches forge build for CRE workflows")
PY

for wf in "${WORKFLOWS[@]}"; do
  wf_dir="$CRE_ROOT/$wf"
  echo "==> [$wf] install + typecheck"
  test -f "$wf_dir/package.json"
  test -f "$wf_dir/workflow.yaml"
  (cd "$wf_dir" && bun install && bun run typecheck)

  if [[ -f "$wf_dir/main.test.ts" ]]; then
    echo "==> [$wf] unit tests"
    (cd "$wf_dir" && bun test)
  fi
done

if [[ "${CRE_SIMULATE:-0}" == "1" ]]; then
  if ! command -v "$CRE_BIN" >/dev/null 2>&1; then
    echo "CRE_SIMULATE=1 but '$CRE_BIN' not found" >&2
    exit 1
  fi

  echo "==> Optional CRE compile check (requires authenticated CRE CLI)"
  for wf in round-scheduler sweep-unclaimed lane-benchmark; do
    echo "==> [$wf] cre workflow simulate (compile-only expectation)"
    set +e
    output="$(
      cd "$CRE_ROOT" && \
      "$CRE_BIN" workflow simulate "$wf" \
        --target staging-settings \
        --non-interactive \
        --trigger-index 0 2>&1
    )"
    status=$?
    set -e
    echo "$output" | tail -20
    if ! echo "$output" | grep -q "Workflow compiled"; then
      echo "Expected 'Workflow compiled' for $wf (exit $status)" >&2
      exit 1
    fi
  done
else
  echo "==> Skipping cre workflow simulate (set CRE_SIMULATE=1 locally after cre login)"
fi

echo "CRE validation complete"
