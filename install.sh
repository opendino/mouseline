#!/usr/bin/env bash
# Installs or updates MouseLine from the latest GitHub release:
#
#   curl -fsSL https://raw.githubusercontent.com/opendino/mouseline/main/install.sh | bash
#
# It downloads the release DMG with curl, checks its SHA-256 against the one GitHub lists
# for the release, quits MouseLine if it is running, copies MouseLine.app to /Applications
# and opens it. Files downloaded with curl are not quarantined, so macOS does not stop the
# first launch the way it does for a DMG downloaded in a browser.
#
# Options (environment variables):
#   MOUSELINE_VERSION=0.1.0     install this version instead of the latest
#   MOUSELINE_DIR=<folder>      install into this folder instead of /Applications
#   MOUSELINE_NO_OPEN=1         do not open MouseLine afterwards
#
# To uninstall, see https://github.com/opendino/mouseline#uninstalling
set -euo pipefail

REPO="opendino/mouseline"
BUNDLE_ID="app.mouseline"

say() { printf '==> %s\n' "$*"; }
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

# Everything runs from main, called on the last line, so a download cut off halfway
# through `curl | bash` runs nothing.
main() {
  [[ "$(uname -s)" == Darwin ]] || fail "MouseLine is a macOS app."
  local macos_major
  macos_major="$(sw_vers -productVersion | cut -d. -f1)"
  (( macos_major >= 13 )) || fail "MouseLine needs macOS 13 or later (this Mac has $(sw_vers -productVersion))."

  local install_dir="${MOUSELINE_DIR:-/Applications}"
  local app="$install_dir/MouseLine.app"
  local work
  work="$(mktemp -d "${TMPDIR:-/tmp}/mouseline-install.XXXXXX")"
  local mount="$work/mount"
  # shellcheck disable=SC2064  # expand now: $work is local to main
  trap "hdiutil detach -quiet '$mount' 2>/dev/null || true; rm -rf '$work'" EXIT

  # --- Find the release -------------------------------------------------------
  local api="https://api.github.com/repos/$REPO/releases/latest"
  if [[ -n "${MOUSELINE_VERSION:-}" ]]; then
    api="https://api.github.com/repos/$REPO/releases/tags/v${MOUSELINE_VERSION#v}"
  fi
  curl -fsSL -H 'Accept: application/vnd.github+json' "$api" -o "$work/release.json" ||
    fail "could not read the release from GitHub ($api)."

  local tag url="" name="" digest="" i=0 asset
  tag="$(plutil -extract tag_name raw -o - "$work/release.json")"
  while asset="$(plutil -extract "assets.$i.name" raw -o - "$work/release.json" 2>/dev/null)"; do
    if [[ "$asset" == MouseLine-*.dmg ]]; then
      name="$asset"
      url="$(plutil -extract "assets.$i.browser_download_url" raw -o - "$work/release.json")"
      digest="$(plutil -extract "assets.$i.digest" raw -o - "$work/release.json" 2>/dev/null || true)"
      break
    fi
    i=$((i + 1))
  done
  [[ -n "$url" ]] || fail "release $tag has no MouseLine DMG."

  # GitHub lists a sha256 digest for each asset; older releases only have it in the notes.
  local expected="${digest#sha256:}"
  if [[ -z "$expected" || "$expected" == "$digest" ]]; then
    expected="$(plutil -extract body raw -o - "$work/release.json" 2>/dev/null |
      sed -n 's/.*SHA-256\*\* `\([0-9a-f]\{64\}\)`.*/\1/p' | head -1)"
  fi
  [[ -n "$expected" ]] || fail "release $tag lists no SHA-256 for $name; not installing an unverified download."

  # --- Download and verify ----------------------------------------------------
  say "Downloading MouseLine ${tag#v}"
  curl -fL --progress-bar "$url" -o "$work/$name" || fail "download failed: $url"
  local actual
  actual="$(shasum -a 256 "$work/$name" | awk '{ print $1 }')"
  [[ "$actual" == "$expected" ]] || fail "checksum mismatch for $name (expected $expected, got $actual)."

  mkdir -p "$mount"
  hdiutil attach -quiet -nobrowse -readonly -noautoopen -mountpoint "$mount" "$work/$name" ||
    fail "could not open $name."
  [[ -d "$mount/MouseLine.app" ]] || fail "$name does not contain MouseLine.app."
  codesign --verify --strict "$mount/MouseLine.app" || fail "MouseLine.app in $name has a broken signature."

  # --- Install ----------------------------------------------------------------
  # Only the copy being replaced has to quit; one running from elsewhere can stay.
  local running="$app/Contents/MacOS/MouseLine"
  if pgrep -qf "^$running"; then
    say "Quitting the running MouseLine"
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
    local _
    for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -qf "^$running" || break; sleep 0.5; done
    if pgrep -qf "^$running"; then
      fail "MouseLine is still running; quit it from its menu bar icon and run this again."
    fi
  fi

  local sudo=()
  mkdir -p "$install_dir" 2>/dev/null || true
  if [[ ! -w "$install_dir" ]]; then
    say "$install_dir is not writable by you; asking for your password"
    sudo=(sudo)
  fi
  say "Installing to $app"
  # Copy next to the old app first, then swap, so a failed copy leaves the old one intact.
  ${sudo[@]+"${sudo[@]}"} rm -rf "$app.installing"
  ${sudo[@]+"${sudo[@]}"} ditto "$mount/MouseLine.app" "$app.installing"
  ${sudo[@]+"${sudo[@]}"} rm -rf "$app"
  ${sudo[@]+"${sudo[@]}"} mv "$app.installing" "$app"

  say "MouseLine ${tag#v} is installed."
  if [[ -z "${MOUSELINE_NO_OPEN:-}" ]]; then
    open "$app"
    echo "It lives in the menu bar. The welcome guide asks for Accessibility access the first time."
  fi
}

main "$@"
