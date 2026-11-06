#!/usr/bin/env bash
# Runs the unit tests. With only the Command Line Tools installed, SwiftPM does not
# find the Swift Testing macro plugin on its own, so its path is passed explicitly.
set -euo pipefail

cd "$(dirname "$0")/.."

args=()
plugin_dir="$(xcode-select -p)/usr/lib/swift/host/plugins/testing"
if [[ -d "$plugin_dir" ]]; then
  args+=(-Xswiftc -plugin-path -Xswiftc "$plugin_dir")
fi

swift test "${args[@]}" "$@"
