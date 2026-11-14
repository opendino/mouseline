# Contributing to MouseLine

Thanks for helping! Bug reports, translations and pull requests are all welcome.

## Reporting a bug

Open an issue with the bug template. The most useful details: macOS version, Mac (Apple
silicon or Intel), mouse model, which gesture and app, what you expected and what
happened. Logs help too:

```bash
log show --last 10m --predicate 'subsystem == "app.mouseline"' --info
```

## Building

Xcode is not required; the Command Line Tools are enough (`xcode-select --install`).

```bash
scripts/test.sh            # unit tests (MouseLineCore)
scripts/build-app.sh       # build/MouseLine.app, universal
scripts/make-dev-cert.sh   # once: a local signing certificate, so rebuilds keep the
                           # Accessibility permission
```

The app needs Accessibility access; see README → Accessibility permission.

To check the UI without clicking through it, render every window to PNG:

```bash
build/MouseLine.app/Contents/MacOS/MouseLine --snapshot /tmp/shots --light
```

## Project layout

- `Sources/MouseLineCore` — pure Swift, no AppKit: recognizer, gesture state machine,
  configuration, calibration. Everything here is unit-tested; new logic belongs here when
  it can.
- `Sources/MouseLine` — the app: event tap, actions, HUD, trail, SwiftUI settings.
- `Tests/MouseLineCoreTests` — Swift Testing.
- `scripts/strings/` — translations (see below).

## Code style

- Small, focused changes with a clear commit message (imperative mood, why over what).
- Doc comments explain *why* something is done, not what the next line does.
- The app must build with the Command Line Tools alone, so SwiftUI macros that need
  Xcode's plugins (`@State`, `@Observable`, `@Entry`, `#Preview`) are not used; use small
  `ObservableObject` models with `@StateObject` / `@ObservedObject`.
- Deployment target is macOS 13. Newer APIs go behind `#available`.
- Every user-visible string goes through SwiftUI literals or `L()` / `LF()`, and gets a
  translation (below). CI fails on missing translations.

## Translations

English is the key in the code. Translations live in `scripts/strings/<lang>.tsv` as
`id: text` lines; `keys.tsv` holds the English text for each id.

```bash
python3 -I scripts/strings.py sync      # after adding UI text: new ids for new strings
python3 -I scripts/strings.py missing   # what each language still lacks
python3 -I scripts/strings.py build     # regenerate Support/*.lproj
python3 -I scripts/check-strings.py     # coverage and placeholders
```

Keep placeholders (`%@`, `%d`, `%.0f`) exactly as in English. Native speakers reviewing an
existing language are especially welcome: most translations were written without one.

## Pull requests

1. Fork, create a branch, make the change.
2. `scripts/test.sh` and `python3 -I scripts/check-strings.py` pass.
3. Describe what changed and how you tested it (gesture, app, macOS version).

By contributing you agree that your contribution is licensed under the Apache License 2.0.
