# MouseLine for Raycast

Control [MouseLine](https://github.com/opendino/mouseline), the mouse gesture app for macOS,
from Raycast.

| Command | What it does |
|---|---|
| Toggle Gestures | Turns gestures on or off |
| Enable Gestures / Disable Gestures | Turns gestures on / off |
| Toggle Gestures in Current App | Pauses gestures in the app you are using (games, 3D tools, remote desktops), or turns them back on |
| Open MouseLine Settings | Opens the settings window |
| Calibrate Gestures | Opens calibration, which fits recognition to how you draw |

Requires MouseLine 0.1.0 or later:

```bash
brew tap opendino/tap
brew trust --cask opendino/tap/mouseline   # Homebrew 7+ asks you to trust third-party casks
brew install --cask mouseline
```

The commands use MouseLine's `mouseline://` URLs, so they also work as hotkeys or quicklinks.
