#!/usr/bin/env bash
# Builds build/mgestures.app from the Swift package.
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
DEV_CERT="mgestures Local Development"
DEV_KEYCHAIN="$HOME/Library/Keychains/mgestures-dev.keychain-db"
SIGN_LABEL="${SIGN_IDENTITY:-}"
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
  # Prefer the local development certificate (scripts/make-dev-cert.sh): its signature
  # stays the same across builds, so the Accessibility permission is kept. It is
  # self-signed and untrusted, so codesign takes it by SHA-1 fingerprint, not by name.
  dev_sha1=""
  if [[ -f "$DEV_KEYCHAIN" ]]; then
    dev_sha1="$(security find-certificate -c "$DEV_CERT" -Z "$DEV_KEYCHAIN" 2>/dev/null | sed -n 's/^SHA-1 hash: //p' | head -1)"
  fi
  if [[ -n "$dev_sha1" ]]; then
    security unlock-keychain -p "" "$DEV_KEYCHAIN"
    SIGN_IDENTITY="$dev_sha1"
    SIGN_LABEL="$DEV_CERT"
  else
    SIGN_IDENTITY="-"   # ad-hoc signature
    SIGN_LABEL="ad hoc"
    echo "note: signing ad hoc; run scripts/make-dev-cert.sh once to keep the Accessibility permission across builds" >&2
  fi
fi
ARCHS="${ARCHS:-arm64 x86_64}"        # space-separated
ENTITLEMENTS="Support/mgestures.entitlements"
APP="build/mgestures.app"
PRODUCT="mgestures"

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

codesign --force --options runtime --timestamp=none \
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
