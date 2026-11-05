# Verification

macOS 15.2, Apple Silicon, Swift 6.1.

```bash
swift test        # 112 tests, 0 failures
./scripts/build.sh
```

Covers grid geometry (inclusive/reverse drags, clamping, multi-display conversion), panel drag routing, centred header, best-effort sizing for minimum-size windows, instant preview, hotkey registration and migration, menu-bar readiness, and that closing the preview overlay leaves ARC as its owner (the 0.2.2–0.3.2 screen-change over-release).

End-to-end check on the installed app: hotkey → real mouse drag → target resized 800×668 → 952×596 while the panel stayed put, then dismissed.

After Effects 2026 (26.5): `--smoke-test-target-pid` against a live AE document window (role `AXLayoutArea`, subrole `AXFloatingWindow`) applied 1680×932.5 at (0, 25) — actual 1680×933 — then the original 3360×1854 frame was restored.

Window-shape audit of every running app (2026-11-02): only Warp published a movable window Gridlet refused (`AXWindow`/`AXSystemDialog`), now accepted; Finder's desktop (`AXScrollArea`) is still refused. Standard `AXWindow`/`AXStandardWindow` apps re-checked end to end: Mail moved to 1680×932.5 and was restored to its 840×1865 frame afterwards.

Space send (2026-11-02): with a Chrome window focused on a hidden Space — yabai reported its frame as 121,25 while Accessibility had it at 113,114 — `--space-send <pid> <space>` resolved the window by CGWindowID and moved it Space 2 → 3 and back. A second Chrome window on the visible Space moved 1 → 3 → 1.

Window hints: the 0.3.8 per-window outlines were reverted at Elliot's request and the tint halved twice (0.3.9, then 0.3.10). Measured back to back on an unchanged desktop, toggling only `showWindowHints`: covered cells sit 6 levels above uncovered ones at the 0.3.10 strength (mean over changed pixels 5.1), against 11 levels at 0.3.9 (mean 9.6). Sample points inside partially covered cells read lower, so compare peaks, not single tiles.

Note: a binary launched straight from `.build/` has no bundle identifier, so `UserDefaults` never sees the app's settings domain — run `~/Applications/Gridlet.app/Contents/MacOS/Gridlet` when a check depends on stored settings.

Not verified: Warp end to end (it had no window open during the check), physical multi-monitor hardware, notarised distribution.
