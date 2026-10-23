#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/dist/Gridlet.app/Contents/MacOS/Gridlet"
OUT="$ROOT/design/native-ui-pass"

if [[ ! -x "$BIN" ]]; then
  echo "Build dist/Gridlet.app first (./scripts/build.sh)" >&2
  exit 1
fi

mkdir -p "$OUT"

render() {
  local appearance="$1"
  local state="$2"
  local screen="$3"
  local outfile="$4"
  echo "==> $outfile"
  "$BIN" --ui-snapshot "$OUT/$outfile" \
    --snapshot-appearance "$appearance" \
    --snapshot-state "$state" \
    --snapshot-screen "$screen"
}

render light idle panel panel-light-idle.png
render dark idle panel panel-dark-idle.png
render dark selected panel panel-dark-selected.png
render light no-target panel panel-light-no-target.png
render light error panel panel-light-error.png
render light idle settings settings-light.png
render light idle permission permission-light.png
render dark idle permission permission-dark.png

cat >"$OUT/CONTACT-SHEET.md" <<EOF
# Native UI contact sheet (Gridlet 0.2.0 build 3)

Generated from production AppKit via \`--ui-snapshot\` (no Screen Recording).

| PNG | Description |
|-----|-------------|
| panel-light-idle.png | Floating panel, light appearance, idle |
| panel-dark-idle.png | Floating panel, dark appearance, idle |
| panel-dark-selected.png | Dark, simulated 4×4 selection block |
| panel-light-no-target.png | Light, no target window |
| panel-light-error.png | Light, compact resize error |
| settings-light.png | Settings window (full native frame, light) |
| permission-light.png | Accessibility permission window (full native frame, light) |
| permission-dark.png | Accessibility permission window (full native frame, dark) |

Footer on preview panels reads **UI preview** (not live resize).
EOF

echo "Wrote PNGs under $OUT"
