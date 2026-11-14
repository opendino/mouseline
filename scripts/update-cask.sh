#!/usr/bin/env bash
# Writes the Homebrew cask for a published release.
#
#   scripts/update-cask.sh 0.1.0 [path/to/homebrew-tap]
#
# Downloads the release DMG from GitHub, computes its SHA-256 and writes
# <tap>/Casks/mouseline.rb from packaging/homebrew/mouseline.rb (default tap path:
# ../homebrew-tap). Commit and push the tap afterwards.
set -euo pipefail

cd "$(dirname "$0")/.."
version="${1:?usage: scripts/update-cask.sh <version> [tap-path]}"
tap="${2:-../homebrew-tap}"
url="https://github.com/opendino/mouseline/releases/download/v${version}/MouseLine-${version}.dmg"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
echo "Downloading $url"
curl -fsSL "$url" -o "$tmp/MouseLine.dmg"
sha="$(shasum -a 256 "$tmp/MouseLine.dmg" | awk '{ print $1 }')"

mkdir -p "$tap/Casks"
sed -e "s/^  version \".*\"/  version \"${version}\"/" \
    -e "s/^  sha256 \".*\"/  sha256 \"${sha}\"/" \
    packaging/homebrew/mouseline.rb > "$tap/Casks/mouseline.rb"
echo "Wrote $tap/Casks/mouseline.rb (version $version, sha256 $sha)"
