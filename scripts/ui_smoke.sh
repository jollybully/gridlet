#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/Gridlet.app/Contents/MacOS/Gridlet"

if [[ ! -x "$APP" ]]; then
  echo "Missing $APP — run ./scripts/build.sh first" >&2
  exit 1
fi

echo "==> Launch UI smoke (Preview test, no resize)"
"$APP" --ui-smoke &
PID=$!

cleanup() {
  kill "$PID" 2>/dev/null || true
  wait "$PID" 2>/dev/null || true
}
trap cleanup EXIT

sleep 2

if ! kill -0 "$PID" 2>/dev/null; then
  echo "Gridlet exited early (crash?)" >&2
  exit 1
fi

# Floating panel window for our PID (CGWindowList — no Automation permission)
panel_found=0
for _ in 1 2 3; do
  if swift "$ROOT/scripts/check_panel_window.swift" "$PID"; then
    panel_found=1
    break
  fi
  sleep 1
done
if [[ "$panel_found" -ne 1 ]]; then
  echo "No Gridlet panel window found for pid $PID" >&2
  exit 1
fi

echo "UI smoke OK (pid $PID alive, floating panel window present)"

kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true
trap - EXIT

echo "==> Launch UI smoke dispatch (sendEvent, panel must not move)"
"$APP" --ui-smoke-dispatch &
DISPATCH_PID=$!
DISPATCH_START=$SECONDS
while kill -0 "$DISPATCH_PID" 2>/dev/null; do
  if (( SECONDS - DISPATCH_START > 15 )); then
    kill "$DISPATCH_PID" 2>/dev/null || true
    echo "ui-smoke-dispatch timed out" >&2
    exit 1
  fi
  sleep 0.2
done
wait "$DISPATCH_PID"
DISPATCH_STATUS=$?
if [[ "$DISPATCH_STATUS" -ne 0 ]]; then
  echo "ui-smoke-dispatch failed (exit $DISPATCH_STATUS)" >&2
  exit 1
fi

echo "UI smoke dispatch OK"
exit 0
