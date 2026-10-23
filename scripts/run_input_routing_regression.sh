#!/usr/bin/env bash
# Outside default `swift test` discovery narrative — records INPUT ROUTING regression gate.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG="$ROOT/verification/input-routing-regression.log"
mkdir -p "$ROOT/verification"

{
  echo "=== Input routing regression $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
  echo "Host: $(uname -m) $(sw_vers -productVersion)"
  echo "Filter: InputRoutingRegressionTests"
  echo
} >"$LOG"

set +e
cd "$ROOT"
swift test --filter InputRoutingRegressionTests 2>&1 | tee -a "$LOG"
STATUS=${PIPESTATUS[0]}
set -e

echo >>"$LOG"
echo "exit_status=$STATUS" >>"$LOG"
if [[ "$STATUS" -eq 0 ]]; then
  echo "(post-fix expected: exit 0)" >>"$LOG"
fi
exit "$STATUS"
