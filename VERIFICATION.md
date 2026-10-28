# Verification

macOS 15.2, Apple Silicon, Swift 6.1.

```bash
swift test        # 79 tests, 0 failures
./scripts/build.sh
```

Covers grid geometry (inclusive/reverse drags, clamping, multi-display conversion), panel drag routing, centred header, best-effort sizing for minimum-size windows, instant preview, hotkey registration and migration, menu-bar readiness, and that closing the preview overlay leaves ARC as its owner (the 0.2.2–0.3.2 screen-change over-release).

End-to-end check on the installed app: hotkey → real mouse drag → target resized 800×668 → 952×596 while the panel stayed put, then dismissed.

Not verified: physical multi-monitor hardware, notarised distribution.
