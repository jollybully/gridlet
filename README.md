# Gridlet

A tiny macOS window manager. Press your shortcut, drag a rectangle on the grid, and the window you were using snaps to that part of the screen.

**Alpha** — works daily, but not notarised. macOS 13+.

![Gridlet dragging a selection](media/gridlet-dragging.png)

## Install

1. Download `Gridlet-0.2.2-macos.zip` from [Releases](../../releases/latest) and unzip it.
2. Move `Gridlet.app` to `/Applications` or `~/Applications`.
3. Right-click → **Open** (ad-hoc signed, so double-click may be blocked once).
4. Enable Gridlet in **System Settings → Privacy & Security → Accessibility**, then quit and reopen it.

   Rebuilding the app changes its ad-hoc signature, and macOS silently drops the
   Accessibility grant when that happens. After `./scripts/build.sh` (or any manual build)
   remove Gridlet from the Accessibility list and add it again — otherwise it launches fine
   but cannot move windows.

## Use

Set your shortcut in **Settings…** (default ⌃⌥Space). Focus a window, press the shortcut, drag on the grid, release. **Esc** cancels. Grid size is configurable (default 8×8).

## Build

```bash
git clone https://github.com/jollybully/gridlet.git && cd gridlet
./scripts/build.sh      # tests, release build, sign → dist/
```

`scripts/build.sh` signs with a **stable local identity** (`Gridlet Dev`, created on first
build by `scripts/dev-signing-identity.sh` in its own throwaway keychain). That matters:
an ad-hoc signature changes on every build, and macOS silently drops the Accessibility
grant when it does, so you would have to re-enable the app after each build. A
certificate keeps the same designated requirement, so the grant survives rebuilds. The
certificate is self-signed and is **not** added to any system trust settings — it exists
only to give builds a consistent identity. If creating it fails, the script falls back to
ad-hoc signing and prints a warning.

The script also adds that keychain to your login keychain search list so `codesign` can
find the identity without prompting.

## Notes

- No networking, analytics or accounts. Settings live in `UserDefaults`.
- Minimum-size windows are moved as close as possible rather than refused.
- Full-screen windows, sheets and the desktop are ignored.
- Not notarised; no Developer ID build.

## Why it exists

I used [Divvy](https://mizage.com/divvy/) for years and loved it — one grid, one drag, done. It no longer works on recent macOS, so this is a from-scratch reimplementation of that workflow. No Divvy code or assets; all credit for the idea to its author. Not affiliated with Mizage.

MIT — see [LICENSE](LICENSE).
