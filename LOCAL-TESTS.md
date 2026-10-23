# Independent local verification

## 0.2.0 native UI build — installed and end-to-end verified

Version 0.2.0 (build 3) was installed at `~/Applications/Gridlet.app` after the owner approved the UI and requested header alignment correction. The installed executable matches the tested `dist` bundle, its signature verifies, the LaunchServices-running process resolves to the installed path, and saved app settings were read back unchanged. The previous 0.1.1 bundle was retained as a rollback copy. After the owner approved the updated app, the stored Accessibility requirement was read back and matched its installed signature. The GUI was restarted via LaunchServices; no permission was granted automatically.

### Checks independently repeated

- `swift test`: **61 XCTest cases, 0 failures** (standard-window + menu readiness pass).
- `codesign --verify --deep --strict` and `plutil -lint`: pass on the review bundle.
- The macOS ZIP passes its CRC checks; its executable is byte-identical to the review bundle.
- Before installation, SHA-256 comparisons confirmed the old installed executable had not changed during UI review. `Geometry.swift` and `WindowTarget.swift` remain byte-identical to the proven pre-UI-pass implementation.
- Native AppKit renders were inspected in light/dark, selected, no-target, error and settings states. The activation hotkey recorder is visible. Light/dark tile visibility was checked from actual rendered pixels; the first faint version was corrected.
- A separate verifier posted ordinary unmodified CGEvent mouse-down, 16 gradual drag events and mouse-up to the new preview process. Selection completed and dismissed the panel; the panel origin remained fixed throughout. The installed app was not stopped, its activation hotkey was not intercepted, and a disposable fixture window was left unchanged as expected in preview mode. See `verification/ui-0.2.0-real-mouse-preview.json`.

### Feature scope

The essential configurable **global activation hotkey** is retained, including persisted bindings, layout-aware key names, transactional registration and recorder cleanup. Presets, per-preset shortcut editors, keyboard grid +/- controls, Option subdivision and Shift inversion were intentionally removed. Tests for the intentionally retired features were removed, while targeted UI, header-alignment and menu-readiness regressions were added. The current total is 61, and the native input-routing and geometry checks remain.

### Native images

`design/native-ui-pass/` contains PNGs rendered from the production AppKit view code. The Safari target in those captures is an explicit example/preview, not evidence of a live Safari window being resized. The contact sheet adds labels around those native renders, not a separate HTML recreation. Live material/vibrancy can vary with the desktop backdrop.

The complete **installed-GUI hotkey → mouse drag → AX resize** workflow passed after approval and relaunch: an ordinary unmodified mouse drag resized a disposable window from 800×668 at (120,379) to 952×596 at (0,46). The new 320×380 Gridlet panel remained at (792,452) throughout and dismissed on release. See `verification/ui-0.2.0-installed-end-to-end.json`. The test used the actual installed LaunchServices process, not preview mode or a CLI resize call.

## Historical 0.1.1 verification

The original user interaction exposed an input-routing defect missed by direct handler tests: AppKit could drag the Gridlet panel rather than deliver the first selection gesture. Four new regression tests failed before the fix; after disabling background/window movement and accepting the grid's first click, **55 tests** passed in that version.

Real native mouse-event comparison reproduced panel movement in the old build and a stationary panel in the corrected build. After the owner approved version 0.1.1, the TCC requirement was read back and matched its signature. The installed GUI was restarted via LaunchServices.

An end-to-end test of that installed 0.1.1 GUI passed: a real unmodified mouse drag resized a disposable target from 800×668 at (120,379) to 952×596 at (0,46); Gridlet remained at (802,467) throughout and dismissed on release. See `verification/input-routing-installed-end-to-end.json`. No TCC data was modified and no permission was granted automatically.

## Limits

- One physical display was connected. Other monitor arrangements have geometry tests, not physical hardware verification.
- App-specific Accessibility/minimum-size behavior can constrain requested geometry; readback reports this rather than calling it successful.
- These are ad-hoc-signed local Apple Silicon builds, not notarized public releases.
- Divvy and its settings are unchanged. No public repository, commit, tag or release was created.
