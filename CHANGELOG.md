# Changelog

All notable changes to MouseLine. Versions follow [Semantic Versioning](https://semver.org).

## Unreleased

- Install script: `curl -fsSL https://raw.githubusercontent.com/opendino/mouseline/main/install.sh | bash`
  installs or updates MouseLine without the Gatekeeper warning.
- Releases are signed with a fixed project certificate, so updates keep the Accessibility
  permission. Updating from 0.1.0 asks for it once more.
- Homebrew installs with one command: `brew install --cask opendino/tap/mouseline`.

## 0.1.0

The first public release.

- Mouse gestures with the right or middle button: 32 built-in shapes (lines, diagonals,
  L corners, U / arch, C, chevrons), a glowing trail, Esc to cancel, hold still for the
  context menu.
- Actions: tile, maximize, center, minimize, close and full-screen windows, move a window
  to the next display; hide or quit apps; back / forward; Mission Control, show desktop,
  lock screen, sleep display; media keys; keyboard shortcuts, open app or URL, shell
  commands and AppleScript.
- Custom gestures, per-app gestures and excluded apps.
- Calibration with the real trigger button: fits recognition to how you draw and keeps
  your strokes as personal examples.
- Recognition test area, global on/off shortcut, required modifier key, sound and haptic
  feedback, launch at login, export / import / reset of settings.
- Settings window in the style of System Settings; Liquid Glass on macOS 26 with
  fallbacks for macOS 13–15; light, dark or system theme.
- 20 languages with an in-app language picker; right-to-left layout for Arabic.
- Universal app (Apple silicon and Intel), macOS 13 or later. No network access.
