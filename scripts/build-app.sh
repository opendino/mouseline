#!/usr/bin/env bash
# Builds build/MouseLine.app from the Swift package.
#
#   scripts/build-app.sh                 # release build, universal (arm64 + x86_64), signed with
#                                        # the local dev certificate if present, else ad hoc
#   ARCHS=arm64 scripts/build-app.sh     # one architecture only (faster local builds)
#   CONFIG=debug scripts/build-app.sh    # debug build
#   SIGN_IDENTITY="Developer ID Application: …" scripts/build-app.sh
#
# Works with the Xcode Command Line Tools alone; Xcode is not required.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
DEV_CERT="MouseLine Local Development"
DEV_KEYCHAIN="$HOME/Library/Keychains/mouseline-dev.keychain-db"
SIGN_LABEL="${SIGN_IDENTITY:-}"
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
  # Prefer the local development certificate (scripts/make-dev-cert.sh): its signature
  # stays the same across builds, so the Accessibility permission is kept. It is
  # self-signed and untrusted, so codesign takes it by SHA-1 fingerprint, not by name.
  dev_sha1=""
  # Before the rename to MouseLine the certificate was "mgestures Local Development" in
  # mgestures-dev.keychain-db; keep using it if that is the one this machine has.
  if [[ ! -f "$DEV_KEYCHAIN" && -f "$HOME/Library/Keychains/mgestures-dev.keychain-db" ]]; then
    DEV_CERT="mgestures Local Development"
    DEV_KEYCHAIN="$HOME/Library/Keychains/mgestures-dev.keychain-db"
  fi
  if [[ -f "$DEV_KEYCHAIN" ]]; then
    dev_sha1="$(security find-certificate -c "$DEV_CERT" -Z "$DEV_KEYCHAIN" 2>/dev/null | sed -n 's/^SHA-1 hash: //p' | head -1)"
  fi
  # codesign only finds identities in keychains on the user's search list (its --keychain
  # option does not change that), so check the list too: the keychain can fall off it,
  # e.g. after a keychain reset. Then signing ad hoc beats failing at codesign.
  dev_on_search_list=false
  if [[ -n "$dev_sha1" ]]; then
    security unlock-keychain -p "" "$DEV_KEYCHAIN"
    identities="$(security find-identity -p codesigning 2>/dev/null || true)"
    if [[ "$identities" == *"$dev_sha1"* ]]; then
      dev_on_search_list=true
    fi
  fi
  if [[ "$dev_on_search_list" == true ]]; then
    SIGN_IDENTITY="$dev_sha1"
    SIGN_LABEL="$DEV_CERT"
  elif [[ -n "$dev_sha1" ]]; then
    SIGN_IDENTITY="-"   # ad-hoc signature
    SIGN_LABEL="ad hoc"
    echo "note: signing ad hoc; $DEV_KEYCHAIN is not on your keychain search list, so codesign cannot use \"$DEV_CERT\". Run scripts/make-dev-cert.sh to add it back" >&2
  else
    SIGN_IDENTITY="-"   # ad-hoc signature
    SIGN_LABEL="ad hoc"
    echo "note: signing ad hoc; run scripts/make-dev-cert.sh once to keep the Accessibility permission across builds" >&2
  fi
fi
ARCHS="${ARCHS:-arm64 x86_64}"        # space-separated
ENTITLEMENTS="Support/MouseLine.entitlements"
APP="build/MouseLine.app"
PRODUCT="MouseLine"

read -r -a arch_list <<< "$ARCHS"
if [[ ${#arch_list[@]} -eq 0 ]]; then
  echo "ARCHS is empty" >&2
  exit 1
fi

# --- Build ------------------------------------------------------------------
#
# Produces $BINARY: a (possibly fat) executable containing every architecture in ARCHS.

if [[ ${#arch_list[@]} -eq 1 ]]; then
  arch="${arch_list[0]}"
  swift build -c "$CONFIG" --arch "$arch"
  BINARY="$(swift build -c "$CONFIG" --arch "$arch" --show-bin-path)/$PRODUCT"
else
  arch_args=()
  for arch in "${arch_list[@]}"; do arch_args+=(--arch "$arch"); done

  # Multi-arch builds with one `swift build` go through xcbuild, which only ships with
  # Xcode. Try it first (it is the faster path when available) and fall back to building
  # each architecture into its own scratch directory and merging them with lipo.
  if swift build -c "$CONFIG" "${arch_args[@]}" 2>/dev/null; then
    BINARY="$(swift build -c "$CONFIG" "${arch_args[@]}" --show-bin-path)/$PRODUCT"
  else
    echo "Multi-arch swift build not available here; building each architecture separately."
    slices=()
    for arch in "${arch_list[@]}"; do
      scratch=".build/arch-$arch"
      swift build -c "$CONFIG" --arch "$arch" --scratch-path "$scratch"
      slices+=("$(swift build -c "$CONFIG" --arch "$arch" --scratch-path "$scratch" --show-bin-path)/$PRODUCT")
    done
    mkdir -p build
    BINARY="build/$PRODUCT.universal"
    lipo -create "${slices[@]}" -output "$BINARY"
  fi
fi

# Fail early if an architecture is missing from the result.
binary_archs="$(lipo -archs "$BINARY")"
for arch in "${arch_list[@]}"; do
  if [[ " $binary_archs " != *" $arch "* ]]; then
    echo "Built binary is missing $arch (has: $binary_archs)" >&2
    exit 1
  fi
done

# --- Bundle -----------------------------------------------------------------

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/$PRODUCT"

# SwiftPM with the Command Line Tools records the deployment target as the SDK version
# (LC_BUILD_VERSION "sdk 13.0"). macOS decides from that field whether an app gets the
# current system design — on macOS 26 the floating Liquid Glass sidebar, toolbar and
# controls — so stamp the SDK that was actually used. The minimum macOS stays the same.
MIN_MACOS="$(vtool -show-build "$APP/Contents/MacOS/$PRODUCT" | awk '/minos/ { print $2; exit }')"
SDK_VERSION="$(xcrun --show-sdk-version)"
if [[ -n "$MIN_MACOS" && -n "$SDK_VERSION" ]]; then
  vtool -set-build-version macos "$MIN_MACOS" "$SDK_VERSION" -replace \
    -output "$APP/Contents/MacOS/$PRODUCT" "$APP/Contents/MacOS/$PRODUCT"
fi
cp Support/Info.plist "$APP/Contents/Info.plist"

if [[ -f Support/AppIcon.icns ]]; then
  cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
else
  echo "warning: Support/AppIcon.icns not found; run: swift scripts/make-icon.swift Support/AppIcon.icns" >&2
fi

# Localized resources (en.lproj, tr.lproj, …), if any.
shopt -s nullglob
for lproj in Support/*.lproj; do
  cp -R "$lproj" "$APP/Contents/Resources/"
done
shopt -u nullglob

# --- Sign -------------------------------------------------------------------
#
# The hardened runtime (--options runtime) is needed for notarization; under it the
# Apple Events entitlement is what lets the "Run AppleScript" action talk to other apps.
# Notarization also requires a secure timestamp, so Developer ID builds ask Apple's
# timestamp server for one (needs a network connection); other builds skip it.

timestamp_flag="--timestamp=none"
if [[ "$SIGN_IDENTITY" == *"Developer ID"* ]]; then
  timestamp_flag="--timestamp"
fi
codesign --force --options runtime "$timestamp_flag" \
  --entitlements "$ENTITLEMENTS" --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --strict --verbose=1 "$APP"
echo "Signed with: $SIGN_LABEL"
echo "Designated requirement: $(codesign -d -r- "$APP" 2>&1 | sed -n 's/^designated => //p')"

echo
echo "Architectures: $(lipo -archs "$APP/Contents/MacOS/$PRODUCT")"
echo "Entitlements:"
codesign -d --entitlements - --xml "$APP" 2>/dev/null | plutil -p - || true
echo
echo "Built $APP"
