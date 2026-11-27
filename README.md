# MouseLine

[![CI](https://github.com/opendino/mouseline/actions/workflows/ci.yml/badge.svg)](https://github.com/opendino/mouseline/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/opendino/mouseline)](https://github.com/opendino/mouseline/releases/latest)
![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-green.svg)](LICENSE)

**Draw a line. Get it done.** Mouse gestures for macOS: hold the **right mouse button** (or
the middle one), draw a shape, release — and a window snaps to half the screen, a page goes
back, music pauses, your shortcut fires. A short click still works normally.

```bash
curl -fsSL https://raw.githubusercontent.com/opendino/mouseline/main/install.sh | bash
```

Installs or updates MouseLine in `/Applications` without the "cannot be opened" warning
macOS shows for apps from the internet that are not notarized yet. Or use Homebrew,
`brew install --cask opendino/tap/mouseline`, or the DMG from the
[latest release](https://github.com/opendino/mouseline/releases/latest); see
[Installation](#installation).

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
  MouseLine warns you when it is too similar to an existing one.
- **Calibration**: draw Left, Right, Up and Down twice each with your real trigger
  button, anywhere on screen. MouseLine fits the recognition tolerance and the minimum
  gesture length to your hand and keeps your strokes as personal examples, so shapes are
  recognized the way you draw them. Nothing runs while the calibration sheet is open.
- **Recognition test area**: draw a stroke with the left mouse button and see the closest
  shapes, their distances, and what would happen — without running anything.
- **Trigger options**: right or middle button, an optional required modifier key
  (⌥ ⌃ ⌘ ⇧), and a global shortcut that turns gestures on and off.
- **Feedback**: optional sound and haptic feedback (Force Touch trackpads) on a recognized
  gesture.
- **20 languages**: English, Türkçe, Español, हिन्दी, Português (Brasil), Deutsch, 日本語, Français,
  Italiano, Русский, Українська, Polski, Nederlands, Bahasa Indonesia, Tiếng Việt, ไทย, 한국어,
  简体中文, 繁體中文 and العربية (right to left). The app follows the macOS language; Settings →
  General → Language picks another one.
- **Light, dark or system** appearance (Settings → Appearance → Theme).
- **Liquid Glass** on macOS 26 (settings sidebar, buttons, HUD, the lens at the tip of
  the trail); blur materials and bordered buttons on macOS 13–15.
- Settings can be exported, imported and reset (Settings → General).

## Privacy

MouseLine makes no network connections and collects nothing. It observes the mouse
buttons system-wide. The keyboard is observed **only while a gesture is being drawn**
(to detect Esc); the rest of the time MouseLine does not see key presses at all. The
on/off shortcut is a registered system hot key, which is delivered only for that exact
combination.

## Actions

| Group | Actions |
|---|---|
| Window | Tile left / right / top / bottom, maximize, center, move to next display, toggle full screen, minimize, close |
| App | Hide, quit (Finder is hidden instead of quit), open an application — optionally a new instance with command-line arguments |
| Navigation | Back / Forward, open a URL |
| System | Mission Control, show desktop, lock screen, sleep display |
| Media | Play / pause, next / previous track, volume up / down, mute |
| Custom | Any keyboard shortcut, a shell command (login `zsh`), an AppleScript |

Window actions act on the focused window of the frontmost app.

**Back / Forward** send ⌘[ / ⌘] to Apple apps that ignore the extra mouse buttons
(Safari, Safari Technology Preview, Finder, System Settings, App Store, Music, Podcasts, TV,
Help Viewer) and mouse buttons 4 / 5 everywhere else: browsers and most other apps
understand them, and they do not collide with editor shortcuts (⌘[ is "outdent" there).
The frontmost app decides.

Default bindings: **Left** / **Right** tile the window, **Up** maximizes, **Down** minimizes.

## Installation

Requirements: macOS 13 or later, on Apple Silicon or Intel.

1. Install MouseLine in one of three ways:
   - **Install script** (recommended until MouseLine is notarized):

     ```bash
     curl -fsSL https://raw.githubusercontent.com/opendino/mouseline/main/install.sh | bash
     ```

     It downloads the latest release with `curl`, checks its SHA-256 against the one GitHub
     lists for the release, copies MouseLine to `/Applications` and opens it; skip to step 4.
     macOS does not stop the first launch, because files downloaded with `curl` are not
     quarantined. Run it again to update. [Read the script](install.sh) first if you like:
     it is short.
   - **Homebrew**: `brew install --cask opendino/tap/mouseline`, then skip to step 3.
   - **DMG**: download `MouseLine-<version>.dmg` from the
     [releases page](https://github.com/opendino/mouseline/releases).
2. Open the DMG and drag **MouseLine** onto the **Applications** folder next to it.
3. Eject the disk image and open MouseLine from `/Applications`. It appears in the menu
   bar, not in the Dock.
4. The welcome guide walks you through the rest: grant **Accessibility** access when macOS
   asks (or in *System Settings → Privacy & Security → Accessibility*, then switch
   MouseLine on), choose the button you draw with, try a gesture and, optionally,
   calibrate. Gestures start working a couple of seconds after access is granted.

### If macOS blocks the app

MouseLine is not notarized by Apple yet, so when it comes from a browser download or
Homebrew, Gatekeeper stops the first launch with a message that Apple cannot check it for
malicious software. The [install script](#installation) avoids this. Otherwise, if you
trust the download:

- **macOS 13 and 14**: right-click (or Control-click) MouseLine in Applications, choose
  **Open**, then **Open** again in the dialog.
- **macOS 15 and later** (right-click → Open no longer skips the check): try to open the
  app once, then go to *System Settings → Privacy & Security*, scroll to *Security* and
  click **Open Anyway** next to the MouseLine message. Confirm with your password.

You only have to do this once per installed version. Notarized releases open normally.

macOS ties the Accessibility permission to the app's signature. Releases after 0.1.0 are
all signed with the same project certificate, so updates keep the permission. Coming from
0.1.0, which was signed ad hoc, grant it once more: remove MouseLine from the Accessibility
list (−) and add it again.

### Uninstalling

1. Quit MouseLine (menu bar icon → Quit MouseLine). If you turned on *Launch at login*, turn it off
   first in Settings → General.
2. Delete `/Applications/MouseLine.app`.
3. Delete the settings folder: `~/Library/Application Support/MouseLine`.
4. Remove MouseLine from *System Settings → Privacy & Security → Accessibility* (select it,
   click −). Optionally, reset its permission from Terminal as well:

   ```bash
   tccutil reset Accessibility app.mouseline
   ```

## Install from source

Requirements: macOS 13 or later and the Xcode Command Line Tools (`xcode-select --install`).
Xcode itself is not needed.

```bash
git clone <this repository>
cd MouseLine
scripts/build-app.sh
open build/MouseLine.app
```

`scripts/build-app.sh` produces a **universal** app (Apple Silicon and Intel) in
`build/MouseLine.app`, with the app icon and any localizations, signed with the hardened
runtime. For a faster build that only targets your own Mac, pick one architecture:

```bash
ARCHS=arm64 scripts/build-app.sh      # or ARCHS=x86_64
```

The app asks for **Automation** permission the first time a "Run AppleScript" action
controls another app; that is a separate, per-app prompt from the Accessibility permission.

On first launch a welcome guide offers to move the app to `/Applications` (needed for
"Launch at login"), walks you through the permission and lets you try a gesture.
Only one copy of MouseLine runs at a time: opening another copy while one runs shows the
running copy's Settings instead, so quit the running copy before launching a new build.

### Accessibility permission

MouseLine needs **Accessibility** access to see mouse events and to move windows.
On first launch the welcome guide (or the menu's **Grant Accessibility Access…**) opens
the system prompt; you can also grant it in
*System Settings → Privacy & Security → Accessibility*. Gestures start working
within a couple of seconds after access is granted — no restart needed.

macOS ties the Accessibility permission to the app's signature. An ad-hoc signature
changes with every build, so **without a stable certificate you have to remove MouseLine
from the Accessibility list and add it again after every rebuild**. Create a local
development certificate once and the build script uses it automatically:

```bash
scripts/make-dev-cert.sh
```

It creates a self-signed certificate in its own keychain
(`~/Library/Keychains/mouseline-dev.keychain-db`, added to your keychain search list) and
leaves your login keychain and trust settings alone. After the first build signed with it,
grant Accessibility once more; later builds keep the permission. If that keychain drops off
the search list (for example after a keychain reset), the build signs ad hoc and says so;
run `scripts/make-dev-cert.sh` again to add it back. To use another identity,
for example an Apple Development certificate:

```bash
SIGN_IDENTITY="Apple Development: you@example.com (TEAMID)" scripts/build-app.sh
```

## Configuration

Settings are stored as JSON in
`~/Library/Application Support/MouseLine/config.json`. The Settings window edits this
file; you can also edit it by hand while the app is not running. Unknown or missing keys
fall back to defaults, and an unreadable file is moved aside to `config.broken.json`.

Per-app gestures are stored under `appBindings` (bundle id → overrides) and custom shapes
under `customGestures` (normalized points); deleting a custom shape removes its bindings.

Recognition is easiest to tune with **Settings → Calibration**: click *Calibrate…*, then
hold your trigger button and draw Left, Right, Up and Down twice each, anywhere on the
screen, the way you normally would. Strokes that are too short or look like another shape
are rejected with a hint. *Save* stores the fitted values and your strokes as personal
examples (`personalSamples` in the config). The welcome guide offers the same step.

The fitted values can also be set by hand under *Advanced* in the Calibration pane
(collapsed by default):

- **Minimum gesture length** — strokes shorter than this are treated as a normal click.
- **Recognition tolerance** — how far a stroke may deviate from the closest shape. Lower
  values mean fewer accidental matches but require more precise drawing.

*Advanced* also shows how many personal examples are stored, and *Reset Recognition*
goes back to the defaults and removes them. The Recognition pane is a test area that
shows the distances for your own strokes.

Settings → General shows where the settings file is and has *Export…*, *Import…* and
*Reset All Settings…*.

## Automation (mouseline:// URLs)

Launchers and scripts can control MouseLine with URLs — this is what the Raycast extension
uses. Only switching gestures and opening windows is possible; a URL can never run a
gesture action.

| URL | Does |
|---|---|
| `mouseline://toggle` | Turn gestures on or off |
| `mouseline://enable`, `mouseline://disable` | Turn gestures on / off |
| `mouseline://toggle-app` | Turn gestures off (or back on) in the frontmost app |
| `mouseline://settings` | Open Settings; add a pane: `/gestures`, `/appearance`, `/recognition`, `/calibration`, `/excluded-apps`, `/general` |
| `mouseline://welcome` | Open the welcome guide |

```bash
open mouseline://toggle
```

## How recognition works

MouseLine uses a rotation-sensitive variant of the
[$1 Unistroke Recognizer](https://depts.washington.edu/acelab/proj/dollar/index.html)
(Wobbrock, Wilson & Li, UIST 2007). A stroke is resampled to 32 evenly spaced points,
centered and scaled uniformly (so straight lines stay straight), and compared point by
point with each template. Rotation is *not* normalized: direction matters, so "Left" and
"Right" are different gestures.

Personal examples from calibration are added as extra templates for their shape, so a
stroke is also compared with the way you drew that shape.

The recognizer lives in the `MouseLineCore` library, which has no AppKit dependency and
is covered by unit tests.

## Development

```bash
swift build                                        # build (host architecture, debug)
scripts/test.sh                                    # run unit tests
python3 -I scripts/check-strings.py                # check that every UI string is translated
python3 -I scripts/strings.py sync                 # add new UI strings to scripts/strings/keys.tsv
python3 -I scripts/strings.py build                # regenerate Support/*.lproj from the tables
CONFIG=debug ARCHS=arm64 scripts/build-app.sh      # quick debug app bundle
scripts/build-app.sh                               # universal release app bundle
swift scripts/make-icon.swift Support/AppIcon.icns # regenerate the app icon
```

`scripts/build-app.sh` options (environment variables):

| Variable | Default | Meaning |
|---|---|---|
| `CONFIG` | `release` | `release` or `debug` |
| `ARCHS` | `arm64 x86_64` | Architectures to build, space-separated. With more than one, the script builds them in one `swift build` when the toolchain supports it, otherwise one by one and merges them with `lipo` |
| `SIGN_IDENTITY` | local dev certificate if present, else `-` (ad hoc) | Code signing identity (name or SHA-1). A name containing "Developer ID" also gets a secure timestamp, which notarization needs |

To check the interface without clicking through it, render every window to PNG
(light or dark; nothing is captured and your settings are not touched):

```bash
build/MouseLine.app/Contents/MacOS/MouseLine --snapshot /tmp/MouseLine-shots --light
```

Add `--onscreen` to show each window briefly in the middle of the screen and capture it
there, so Liquid Glass and blur are included, and `--only settings-gestures,hud` to limit
the windows.

The app icon is drawn in code by `scripts/make-icon.swift` (AppKit, no design tools needed)
and checked in as `Support/AppIcon.icns`; rerun the script after changing it.

Project layout:

```
Sources/MouseLineCore/   recognizer, templates, gesture state machine, configuration (pure Swift)
Sources/MouseLine/       menu bar app: event tap, trail overlay, actions, settings UI
Tests/                   unit tests (Swift Testing)
Support/                 Info.plist, entitlements, app icon, en/tr string tables
scripts/                 build, release, test, string and icon helpers
```

### Coming from the Hammerspoon script?

MouseLine started as a Hammerspoon `gestures.lua` script. If you still have that script
loaded, disable it before running MouseLine — otherwise both will try to capture the
right mouse button.

### Localization

UI strings are English in the code and used as keys. SwiftUI literals are looked up
automatically; other strings go through `L()` / `LF()` (`Sources/MouseLine/Localization.swift`).

Translations live in `scripts/strings/`: `keys.tsv` numbers every English string once, and
each language has a table (`de.tsv`, `zh-Hans.tsv`, …) of `id: translation` lines, so a
translator only touches one small file. `plist.*` ids are Info.plist texts
(`InfoPlist.strings`).

```bash
python3 -I scripts/strings.py sync      # after adding UI text: new strings get the next ids
python3 -I scripts/strings.py missing   # ids each language still lacks
python3 -I scripts/strings.py build     # write Support/<lang>.lproj/*.strings
python3 -I scripts/check-strings.py     # coverage and placeholder check per language
```

To add a language: create `scripts/strings/<lang>.tsv`, add it to `LANGUAGES` in
`scripts/strings.py`, to `AppLanguage.all` in `Sources/MouseLine/Settings/LanguageSettings.swift`
and to `CFBundleLocalizations` in `Support/Info.plist`. Translations of new languages are
welcome as pull requests; native speakers reviewing the existing ones are even more welcome.

## Releasing

`scripts/make-release.sh` builds a universal release app and packs it into
`dist/MouseLine-<version>.dmg` (the app plus a link to `/Applications`). The version is
`CFBundleShortVersionString` from `Support/Info.plist`; bump it (and `CFBundleVersion`)
first. The script prints the DMG path and its SHA-256.

For a release users can open without a Gatekeeper warning you need an Apple Developer
Program membership:

1. Create a **Developer ID Application** certificate (developer.apple.com → Certificates)
   and install it in your login keychain. `security find-identity -v -p codesigning` shows
   its full name.
2. Store notarization credentials in the keychain once, with an app-specific password
   from appleid.apple.com:

   ```bash
   xcrun notarytool store-credentials MouseLine \
     --apple-id you@example.com --team-id TEAMID
   ```

3. Build, sign, notarize and staple:

   ```bash
   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
   NOTARY_PROFILE=MouseLine scripts/make-release.sh
   ```

Pass the identity by name: Developer ID is recognized from the name, and only then are
the app and the DMG signed with a secure timestamp. Without `NOTARY_PROFILE` the DMG is
signed but not notarized, and the script prints the commands to notarize it later.
Without `SIGN_IDENTITY` the release is signed **ad hoc** (never with the local development
certificate) and the script warns that it is not notarized: users will have to open it as
described under [If macOS blocks the app](#if-macos-blocks-the-app).

### Release signing without a Developer ID

Until there is a Developer ID, GitHub Actions signs releases with the project's own
self-signed certificate. It does not satisfy Gatekeeper, but it never changes, so the
Accessibility permission survives updates (an ad hoc signature changes with every build).

1. Create it once, which also stores it as the repository secrets `RELEASE_SIGNING_P12`
   and `RELEASE_SIGNING_P12_PASSWORD` (needs `gh` with access to the repository):

   ```bash
   scripts/make-release-cert.sh --set-secrets
   ```

2. Back up `~/.mouseline-release-signing` (a password manager is a good place). Losing it
   means a new signature and one more Accessibility prompt for every user; anyone who has
   it can sign apps that macOS treats as MouseLine, so never commit it.

`.github/workflows/release.yml` imports it with `scripts/import-release-cert.sh`; without
the secrets (forks) it signs ad hoc. Run the workflow by hand (*Actions → Release → Run
workflow*) for a dry run that builds and signs the DMG without publishing it.

## Roadmap

See [docs/FEATURES.md](docs/FEATURES.md). Still open: a notarized release (needs a
Developer ID), which also unlocks the official Homebrew cask (`brew install --cask mouseline`
without a tap), and automatic updates.

## License

Apache License 2.0 — see [LICENSE](LICENSE) and [NOTICE](NOTICE).
