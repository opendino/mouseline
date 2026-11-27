#!/usr/bin/env bash
# CI only: puts the release signing certificate (scripts/make-release-cert.sh) into a
# temporary keychain so codesign can use it, and prints its SHA-1 fingerprint.
#
#   RELEASE_SIGNING_P12=<base64> RELEASE_SIGNING_P12_PASSWORD=<password> \
#     scripts/import-release-cert.sh
#
# Meant for a throwaway runner: it adds a keychain to the user's search list and does not
# remove it. Pass the printed fingerprint to scripts/make-release.sh as SIGN_IDENTITY
# (the certificate is self-signed and untrusted, so codesign takes it by fingerprint).
set -euo pipefail

: "${RELEASE_SIGNING_P12:?is not set}"
: "${RELEASE_SIGNING_P12_PASSWORD:?is not set}"

dir="${RUNNER_TEMP:-$(mktemp -d)}"
keychain="$dir/release-signing.keychain-db"
p12="$dir/release-signing.p12"
keychain_password="$(openssl rand -hex 24)"

printf '%s' "$RELEASE_SIGNING_P12" | base64 --decode > "$p12"

security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings "$keychain"   # no auto-lock during the build
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$p12" -k "$keychain" -P "$RELEASE_SIGNING_P12_PASSWORD" -T /usr/bin/codesign >&2
# Lets codesign use the key without a confirmation dialog.
security set-key-partition-list -S apple-tool:,apple: -s -k "$keychain_password" "$keychain" >/dev/null
rm -f "$p12"

# codesign only finds identities in keychains on the search list.
existing=()
while IFS= read -r line; do
  line="${line#"${line%%[![:space:]]*}"}"; line="${line%\"}"; line="${line#\"}"
  [[ -n "$line" ]] && existing+=("$line")
done < <(security list-keychains -d user)
security list-keychains -d user -s "$keychain" ${existing[@]+"${existing[@]}"}

sha1="$(security find-identity -p codesigning "$keychain" | awk '/MouseLine Release Signing/ { print $2; exit }')"
if [[ -z "$sha1" ]]; then
  echo "error: no \"MouseLine Release Signing\" identity in the imported certificate" >&2
  security find-identity -p codesigning "$keychain" >&2
  exit 1
fi
echo "$sha1"
