#!/usr/bin/env bash
# Builds build/mgestures.app from the Swift package.
#
#   scripts/build-app.sh                 # release build, universal (arm64 + x86_64), ad-hoc signed
#   ARCHS=arm64 scripts/build-app.sh     # one architecture only (faster local builds)
#   CONFIG=debug scripts/build-app.sh    # debug build
#   SIGN_IDENTITY="Developer ID Application: …" scripts/build-app.sh
#
# Works with the Xcode Command Line Tools alone; Xcode is not required.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"   # "-" = ad-hoc signature
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

echo
echo "Architectures: $(lipo -archs "$APP/Contents/MacOS/$PRODUCT")"
echo "Entitlements:"
codesign -d --entitlements - --xml "$APP" 2>/dev/null | plutil -p - || true
echo
echo "Built $APP"
