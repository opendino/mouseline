# mgestures

> Working title. The final name is not decided yet.

Mouse gestures for macOS. Hold the **right mouse button** (or the middle one), draw a
shape, release — and a window snaps to half the screen, an app opens, a shortcut fires,
music pauses. A short click still works normally.

- Lives in the menu bar, no Dock icon.
- 32 built-in shapes: lines, diagonals, L corners, U / arch, C, chevrons — each in
  both drawing directions.
- A glowing trail follows the cursor while you draw (color and width are adjustable).
- Press **Esc** while drawing to cancel.
- Every shape can be bound to an action from the Settings window. Shapes without an
  action are ignored: drawing one simply gives you a normal right click.
- **Hold still to open the context menu**: press and hold without moving and the menu
  opens right away, so press–drag–release menu selection keeps working.
- **Excluded apps**: turn gestures off in apps where right-dragging matters (3D tools,
  games, remote desktops, virtual machines). The app under the cursor decides. The menu bar
  icon has a one-click "Disable in *current app*" toggle.
- **Per-app gestures**: override any shape for one app (e.g. Left = Back in Finder,
  but Tile Left everywhere else), or turn it off there.
- **Custom gestures**: draw your own shape in Settings and give it a name and an action.
  mgestures warns you when it is too similar to an existing one.
- **Try tab**: draw a stroke and see the closest shapes, their distances, and what would
  happen — without running anything.
- **Trigger options**: right or middle button, an optional required modifier key
  (⌥ ⌃ ⌘ ⇧), and a global shortcut that turns gestures on and off.
- **Feedback**: optional sound and haptic feedback (Force Touch trackpads) on a recognized
  gesture.
- **English and Turkish** interface, following the system language.
- Settings can be exported, imported and reset.

## Privacy

mgestures makes no network connections and collects nothing. It observes the mouse
buttons system-wide. The keyboard is observed **only while a gesture is being drawn**
(to detect Esc); the rest of the time mgestures does not see key presses at all. The
on/off shortcut is a registered system hot key, which is delivered only for that exact
combination.

## Actions

| Group | Actions |
|---|---|
| Window | Tile left / right / top / bottom, maximize, center, move to next display, toggle full screen, minimize, close |
| App | Hide, quit (Finder is hidden instead of quit), open an application — optionally a new instance with command-line arguments |
| Navigation | Back / Forward (mouse buttons 4 / 5, which browsers and Finder understand regardless of their keyboard shortcuts), open a URL |
| System | Mission Control, show desktop, lock screen, sleep display |
| Media | Play / pause, next / previous track, volume up / down, mute |
| Custom | Any keyboard shortcut, a shell command (login `zsh`), an AppleScript |

Window actions act on the focused window of the frontmost app.

Default bindings: **Left** / **Right** tile the window, **Up** maximizes, **Down** minimizes.

## Install from source

Requirements: macOS 13 or later and the Xcode Command Line Tools (`xcode-select --install`).
Xcode itself is not needed.

```bash
git clone <this repository>
cd mgestures
scripts/build-app.sh
open build/mgestures.app
```

`scripts/build-app.sh` produces a **universal** app (Apple Silicon and Intel) in
`build/mgestures.app`, with the app icon and any localizations, signed with the hardened
runtime. For a faster build that only targets your own Mac, pick one architecture:

```bash
ARCHS=arm64 scripts/build-app.sh      # or ARCHS=x86_64
```

The app asks for **Automation** permission the first time a "Run AppleScript" action
controls another app; that is a separate, per-app prompt from the Accessibility permission.

On first launch a welcome guide offers to move the app to `/Applications` (needed for
"Launch at login"), walks you through the permission and lets you try a gesture.
Only one copy of mgestures runs at a time: quit the running copy before launching a new build.

### Accessibility permission

mgestures needs **Accessibility** access to see mouse events and to move windows.
On first launch macOS asks for it; you can also grant it in
*System Settings → Privacy & Security → Accessibility*. Gestures start working
within a couple of seconds after access is granted — no restart needed.

macOS ties the Accessibility permission to the app's signature. An ad-hoc signature
changes with every build, so **without a stable certificate you have to remove mgestures
from the Accessibility list and add it again after every rebuild**. Create a local
development certificate once and the build script uses it automatically:

```bash
scripts/make-dev-cert.sh
```

It creates a self-signed certificate in its own keychain
(`~/Library/Keychains/mgestures-dev.keychain-db`, added to your keychain search list) and
leaves your login keychain and trust settings alone. After the first build signed with it,
grant Accessibility once more; later builds keep the permission. To use another identity,
for example an Apple Development certificate:

```bash
SIGN_IDENTITY="Apple Development: you@example.com (TEAMID)" scripts/build-app.sh
```

## Configuration

Settings are stored as JSON in
`~/Library/Application Support/mgestures/config.json`. The Settings window edits this
file; you can also edit it by hand while the app is not running. Unknown or missing keys
fall back to defaults, and an unreadable file is moved aside to `config.broken.json`.

Per-app gestures are stored under `appBindings` (bundle id → overrides) and custom shapes
under `customGestures` (normalized points); deleting a custom shape removes its bindings.

Recognition has two knobs (Settings → General):

- **Minimum gesture length** — strokes shorter than this are treated as a normal click.
- **Recognition tolerance** — how far a stroke may deviate from the closest shape. Lower
  values mean fewer accidental matches but require more precise drawing. The Try tab shows
  the distances for your own strokes.

## How recognition works

mgestures uses a rotation-sensitive variant of the
[$1 Unistroke Recognizer](https://depts.washington.edu/acelab/proj/dollar/index.html)
(Wobbrock, Wilson & Li, UIST 2007). A stroke is resampled to 32 evenly spaced points,
centered and scaled uniformly (so straight lines stay straight), and compared point by
point with each template. Rotation is *not* normalized: direction matters, so "Left" and
"Right" are different gestures.

The recognizer lives in the `MGesturesCore` library, which has no AppKit dependency and
is covered by unit tests.

## Development

```bash
swift build                                        # build (host architecture, debug)
scripts/test.sh                                    # run unit tests
python3 -I scripts/check-strings.py                # check that every UI string is translated
python3 -I scripts/tr_strings.py                   # regenerate Support/tr.lproj from its table
CONFIG=debug ARCHS=arm64 scripts/build-app.sh      # quick debug app bundle
scripts/build-app.sh                               # universal release app bundle
swift scripts/make-icon.swift Support/AppIcon.icns # regenerate the app icon
```

`scripts/build-app.sh` options (environment variables):

| Variable | Default | Meaning |
|---|---|---|
| `CONFIG` | `release` | `release` or `debug` |
| `ARCHS` | `arm64 x86_64` | Architectures to build, space-separated. With more than one, the script builds them in one `swift build` when the toolchain supports it, otherwise one by one and merges them with `lipo` |
| `SIGN_IDENTITY` | local dev certificate if present, else `-` (ad hoc) | Code signing identity (name or SHA-1) |

The app icon is drawn in code by `scripts/make-icon.swift` (AppKit, no design tools needed)
and checked in as `Support/AppIcon.icns`; rerun the script after changing it.

Project layout:

```
Sources/MGesturesCore/   recognizer, templates, gesture state machine, configuration (pure Swift)
Sources/mgestures/       menu bar app: event tap, trail overlay, actions, settings UI
Tests/                   unit tests (Swift Testing)
Support/                 Info.plist, entitlements, app icon, en/tr string tables
scripts/                 build, test and icon helpers
```

### Coming from the Hammerspoon script?

mgestures started as a Hammerspoon `gestures.lua` script. If you still have that script
loaded, disable it before running mgestures — otherwise both will try to capture the
right mouse button.

### Localization

UI strings are English in the code and used as keys. SwiftUI literals are looked up
automatically; other strings go through `L()` / `LF()` (`Sources/mgestures/Localization.swift`).
Turkish translations live in `scripts/tr_strings.py`, which writes
`Support/tr.lproj/Localizable.strings`; `scripts/check-strings.py` reports missing keys and
placeholder mismatches. To add a language, add a `<lang>.lproj/Localizable.strings` and the
language code to `CFBundleLocalizations` in `Support/Info.plist`.

## Roadmap

See [docs/FEATURES.md](docs/FEATURES.md). Still open: Developer ID signing and
notarization, DMG releases with CI, automatic updates, and a Homebrew cask.

## License

Apache License 2.0 — see [LICENSE](LICENSE) and [NOTICE](NOTICE).
