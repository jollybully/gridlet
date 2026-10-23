# Gridlet verification report

**Date:** 2026-10-23 (0.2.0 build 3: standard windows + menu bar readiness)  
**Host:** arm64 macOS 15.2 (Apple Silicon)  
**Toolchain:** Swift 6.1 / Xcode 16.3  

## Commands run

```bash
cd "."
./scripts/run_input_routing_regression.sh   # pre-fix fail log preserved separately
swift test
./scripts/build.sh
plutil -lint dist/Gridlet.app/Contents/Info.plist
codesign --verify --verbose dist/Gridlet.app
```

## Standard windows (permission + settings)

Removed nested `PanelChromeView` from titled utility windows. Permission and settings use plain `windowBackgroundColor` content with ~24pt padding; only the floating grid keeps popover chrome. Permission copy states quit/reopen **once**; primary **Open Accessibility Settings** + secondary **Quit Gridlet** (explicit clicks only).

Measured frames (points, after `layoutIfNeeded`):

| Window | Content size | Frame height (includes title bar) |
|--------|--------------|-----------------------------------|
| Permission | 400×260 | > content + 20 |
| Settings | 340×380 | > content + 20 |

Native PNGs (full theme frame via `StandardWindowLayout.snapshotRoot`): `design/native-ui-pass/permission-light.png`, `permission-dark.png`, updated `settings-light.png` (680×816 px @2×).

## Menu bar

Status icon opens a conventional `NSMenu` (left/right): disabled status row from AX trust + `HotKeyManager.isRegistered`, **Show Grid**, Settings…, Quit. Preview/smoke runs skip menu install and global hotkey registration so they do not steal the owner’s shortcut.

**Ice / discoverability:** Gridlet does not modify Ice or menu-bar ordering. If Ice (or similar) relocates icons off-screen (negative AX positions), use **Show Grid** from the menu after locating the icon, or rely on the configured activation hotkey once registered.

## Header alignment (0.2.0 build 3)

Replaced the header’s fixed `centerX - 52` icon offset with `TargetAppHeaderView`: 22×22 icon, 6pt spacer, 13pt semibold title, centered as one group between close/settings (`verification/header-alignment.json`). Measured `centerDelta` (group midX − panel midX @ 320pt): Safari **0**, Visual Studio Code **0.25**, very long name **0**, No window **0.25** (all ≤ 1pt). Diagnostic: `Gridlet --header-alignment-json <path>`.

## Issues fixed (0.2.0 review)

**Key input:** Borderless `NSPanel` with `[.nonactivatingPanel, .borderless, .fullSizeContentView]` reports `canBecomeKey == false` by default, so Escape/focus routing failed in real AppKit despite `sendEvent` mouse tests passing. `GridPanelWindow` now overrides `canBecomeKey` → `true`, `canBecomeMain` → `false` (nonactivating + immovable panel unchanged).

**Grid contrast:** Idle tiles use appearance-resolved `labelColor` fill (~14% opacity) plus subtle edge stroke; native PNG sampling (2× `panel-light-idle.png`) tile `(195,195,195)` vs gap `(234,234,234)` → **39** RGB levels; dark idle tile `(79,79,79)` vs gap `(44,44,44)` → **35**.

**Chrome:** Close/settings SF Symbols use template + `contentTintColor = .secondaryLabelColor`.

**No target:** Footer hint **Select a window first** (not “Drag to resize”); selection % hidden until a target exists.

## Issue fixed (INPUT ROUTING)

Dragging on the grid moved the **Gridlet panel** instead of selecting cells because `GridPanelWindow` had `isMovableByWindowBackground = true` and `GridView` used AppKit defaults (`mouseDownCanMoveWindow == true`, `acceptsFirstMouse == false`). On a nonactivating floating panel, that competed with rectangle selection—especially on the first click while inactive.

**Fix:** `isMovable = false`, `isMovableByWindowBackground = false`; `GridView` overrides `mouseDownCanMoveWindow` → `false` and `acceptsFirstMouse` → `true`.

Pre-fix failure proof: `verification/input-routing-regression-prefix.log`. Post-fix gate: `verification/input-routing-regression.log` (via `./scripts/run_input_routing_regression.sh`).

## Test results

| Suite | Tests | Failures |
|-------|-------|----------|
| GeometryTests | 11 | 0 |
| GridViewTests | 7 | 0 |
| LiveGridDimensionsTests | 1 | 0 |
| PreviewOverlayTests | 1 | 0 |
| SettingsTests | 12 | 0 |
| DiagnosticsTests | 4 | 0 |
| HotKeyTests | 6 | 0 |
| HotKeyRecorderLifecycleTests | 4 | 0 |
| **InputRoutingRegressionTests** | **5** | **0** |
| PanelCoordinatorSmokeEscapeTests | 1 | 0 |
| **HeaderAlignmentTests** | **4** | **0** |
| **PermissionWindowTests** | **3** | **0** |
| **MenuBarReadinessTests** | **2** | **0** |
| **Total (XCTest)** | **61** | **0** |

`InputRoutingRegressionTests` includes `canBecomeKey` / `canBecomeMain` assertions plus `NSApplication.sendEvent` integration (grid drag does not change panel origin; first click commits while panel is not key; Escape dismisses via coordinator).

Note: Parent review pass cited **49** XCTest cases; **51** after input-routing/contrast pass; **54** after header alignment; **61** after standard-window/menu pass (+7).

Installed `~/Applications/Gridlet.app` executable SHA-256 unchanged: `5b990ebfa46444f37eb7bd84dc2ecc086c6499c8b34d7f57fe205776d836db24`.

## Build artifacts

| Artifact | Path |
|----------|------|
| Application bundle | `./dist/Gridlet.app` |
| Zip | `./dist/Gridlet-0.2.0-macos.zip` |
| Header frames | `./verification/header-alignment.json` |
| Bundle ID | `org.gridlet.Gridlet` |
| Version | `0.2.0` (review build; see `dist/Gridlet.app`) |
| Signing | Ad hoc `codesign --force --deep --sign -` (verified OK) |

## UI smoke (`./scripts/ui_smoke.sh`)

- `Gridlet --ui-smoke`: process alive; floating panel window found (CGWindowList, retried).
- `Gridlet --ui-smoke-dispatch`: in-process `sendEvent` grid drag; panel origin stable and ≥1 commit.

## Limitations

- `sendEvent` / `--ui-smoke-dispatch` do not replace real CGEvent drags with `flags=[]`; parent verification should still assert target resize and unchanged panel origin under Accessibility.
- Ad hoc rebuild changes code identity; re-approve Accessibility after install if macOS requires it.
- Installed `~/Applications/Gridlet.app` was not modified during this build.

## Git

Repository initialized at project root; **no commits**, **no remote**.
