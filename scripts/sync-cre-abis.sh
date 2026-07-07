#!/usr/bin/env bash
# Sync canonical CRE ABIs into each workflow bundle directory.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SHARED="$ROOT/cre/lane-checker-cre/shared"
for wf in round-scheduler hop-monitor settlement hop-sender; do
  cp "$SHARED/lane-controller-abi.ts" "$ROOT/cre/lane-checker-cre/$wf/lane-controller-abi.ts"
  echo "synced lane-controller-abi.ts -> $wf"
done
cp "$SHARED/lane-executor-abi.ts" "$ROOT/cre/lane-checker-cre/hop-sender/lane-executor-abi.ts"
echo "synced lane-executor-abi.ts -> hop-sender"
