#!/usr/bin/env bash
# Builds a distributable release: dist/MouseLine-<version>.dmg.
#
#   scripts/make-release.sh
#       Ad hoc signed, not notarized. Fine for testing; users get a Gatekeeper warning.
#
#   SIGN_IDENTITY=<SHA-1 of the release signing certificate> scripts/make-release.sh
#       Signed with the project's fixed self-signed certificate, as GitHub Actions does
#       (scripts/make-release-cert.sh): not notarized, but the Accessibility permission
#       survives updates.
#
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" scripts/make-release.sh
#       Signed with Developer ID (app and DMG), ready to notarize.
#
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=MouseLine \
#     scripts/make-release.sh
#       Also notarizes the DMG with notarytool and staples the ticket to it. Create the
#       keychain profile once with:
#         xcrun notarytool store-credentials MouseLine --apple-id <id> --team-id <TEAMID>
#
# The version comes from CFBundleShortVersionString in Support/Info.plist. Unlike
# scripts/build-app.sh, this script never signs with the local development certificate:
# without SIGN_IDENTITY it signs ad hoc.
set -euo pipefail

cd "$(dirname "$0")/.."

PLIST="Support/Info.plist"
APP="build/MouseLine.app"
DIST="dist"

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")"
if [[ -z "$VERSION" ]]; then
  echo "error: CFBundleShortVersionString is empty in $PLIST" >&2
  exit 1
fi
DMG="$DIST/MouseLine-$VERSION.dmg"
VOLUME_NAME="MouseLine $VERSION"

warn() { printf 'warning: %s\n' "$*" >&2; }

# --- Identity ---------------------------------------------------------------

IDENTITY="${SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="-"
  warn "SIGN_IDENTITY is not set: signing ad hoc."
  warn "This build is NOT notarized. Users will see a Gatekeeper warning on first launch"
  warn "and have to open it with right-click > Open or System Settings > Privacy & Security > Open Anyway."
fi

# Developer ID is detected from the identity's name (scripts/build-app.sh uses the same
# test to request a secure timestamp), so pass the identity by name, not by SHA-1.
is_developer_id=false
if [[ "$IDENTITY" == *"Developer ID Application"* ]]; then
  is_developer_id=true
elif [[ "$IDENTITY" != "-" ]]; then
  # For example the project's self-signed release certificate (scripts/make-release-cert.sh),
  # passed by SHA-1: it keeps the Accessibility permission across updates, nothing more.
  warn "\"$IDENTITY\" is not a Developer ID Application identity (by name): the build cannot be notarized,"
  warn "and users will see a Gatekeeper warning."
fi

# --- Build ------------------------------------------------------------------

echo "==> Building MouseLine $VERSION"
CONFIG=release SIGN_IDENTITY="$IDENTITY" scripts/build-app.sh

built_version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
if [[ "$built_version" != "$VERSION" ]]; then
  echo "error: $APP has version $built_version, expected $VERSION" >&2
  exit 1
fi

# --- Disk image -------------------------------------------------------------

echo "==> Creating $DMG"
mkdir -p "$DIST"
staging="$(mktemp -d "${TMPDIR:-/tmp}/MouseLine-dmg.XXXXXX")"
trap 'rm -rf "$staging"' EXIT

# ditto keeps the signature, extended attributes and symlinks intact.
ditto "$APP" "$staging/MouseLine.app"
ln -s /Applications "$staging/Applications"

rm -f "$DMG"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$staging" \
  -fs HFS+ \
  -format UDZO \
  -ov \
  "$DMG"

# --- Sign and notarize ------------------------------------------------------

if $is_developer_id; then
  echo "==> Signing the disk image"
  codesign --force --timestamp --sign "$IDENTITY" "$DMG"
  codesign --verify --verbose=1 "$DMG"

  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    echo "==> Notarizing (this can take a few minutes)"
    # notarytool can exit 0 for a rejected submission, so check the status it reports.
    if ! result="$(xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait --output-format plist)"; then
      echo "error: notarytool submit failed" >&2
      [[ -n "${result:-}" ]] && echo "$result" >&2
      exit 1
    fi
    status="$(plutil -extract status raw -o - - <<< "$result" 2>/dev/null || true)"
    submission_id="$(plutil -extract id raw -o - - <<< "$result" 2>/dev/null || true)"
    echo "Notarization status: ${status:-unknown} (submission ${submission_id:-unknown})"
    if [[ "$status" != "Accepted" ]]; then
      echo "error: notarization was not accepted. See the log with:" >&2
      echo "  xcrun notarytool log ${submission_id:-<submission-id>} --keychain-profile \"$NOTARY_PROFILE\"" >&2
      exit 1
    fi

    echo "==> Stapling the ticket"
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG" || \
      warn "spctl did not accept the disk image; check the output above."
  else
    echo
    echo "Not notarized: NOTARY_PROFILE is not set. To notarize this DMG:"
    echo "  xcrun notarytool store-credentials <profile> --apple-id <apple-id> --team-id <TEAMID>   # once"
    echo "  xcrun notarytool submit \"$DMG\" --keychain-profile <profile> --wait"
    echo "  xcrun stapler staple \"$DMG\""
    echo "or rerun this script with NOTARY_PROFILE=<profile>."
  fi
fi

# --- Summary ----------------------------------------------------------------

echo
echo "Release: $DMG"
echo "SHA-256: $(shasum -a 256 "$DMG" | awk '{ print $1 }')"
if ! $is_developer_id; then
  warn "not notarized; users will see a Gatekeeper warning (see README: Installation)."
fi
