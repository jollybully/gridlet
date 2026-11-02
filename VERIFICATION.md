# Verification

macOS 15.2, Apple Silicon, Swift 6.1.

```bash
swift test        # 98 tests, 0 failures
./scripts/build.sh
```

Covers grid geometry (inclusive/reverse drags, clamping, multi-display conversion), panel drag routing, centred header, best-effort sizing for minimum-size windows, instant preview, hotkey registration and migration, menu-bar readiness, and that closing the preview overlay leaves ARC as its owner (the 0.2.2–0.3.2 screen-change over-release).

End-to-end check on the installed app: hotkey → real mouse drag → target resized 800×668 → 952×596 while the panel stayed put, then dismissed.

After Effects 2026 (26.5): `--smoke-test-target-pid` against a live AE document window (role `AXLayoutArea`, subrole `AXFloatingWindow`) applied 1680×932.5 at (0, 25) — actual 1680×933 — then the original 3360×1854 frame was restored.

Window-shape audit of every running app (2026-11-02): only Warp published a movable window Gridlet refused (`AXWindow`/`AXSystemDialog`), now accepted; Finder's desktop (`AXScrollArea`) is still refused. Standard `AXWindow`/`AXStandardWindow` apps re-checked end to end: Mail moved to 1680×932.5 and was restored to its 840×1865 frame afterwards.

Not verified: Warp end to end (it had no window open during the check), physical multi-monitor hardware, notarised distribution.
