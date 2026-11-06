#!/usr/bin/env bash
# Creates a self-signed code signing certificate for local development builds.
#
#   scripts/make-dev-cert.sh
#
# Why: an ad-hoc signature changes with every build, and macOS ties the Accessibility
# permission to the signature, so each rebuild loses the permission. A certificate that
# stays the same gives the app a stable designated requirement
# (identifier "dev.mgestures.app" and certificate leaf = …), so the permission survives
# rebuilds. scripts/build-app.sh uses this certificate automatically once it exists.
#
# The certificate and its private key live in their own keychain,
# ~/Library/Keychains/mgestures-dev.keychain-db, which has an empty password so builds
# can unlock it without a prompt, and is added to your keychain search list (codesign only
# looks there). Your login keychain and trust settings are not changed; the certificate stays
# untrusted, which is fine because builds sign with its SHA-1 fingerprint.
# Anything running as your user can sign with it; that matters only for apps you grant
# permissions to while they carry this signature. Delete the keychain to undo everything:
#
#   security delete-keychain ~/Library/Keychains/mgestures-dev.keychain-db
#   (this also removes it from the search list)
#
# This is for your own machine only. Releases need a Developer ID certificate.
set -euo pipefail

NAME="mgestures Local Development"
KEYCHAIN="$HOME/Library/Keychains/mgestures-dev.keychain-db"

if [[ -f "$KEYCHAIN" ]] && security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "Certificate \"$NAME\" already exists in $KEYCHAIN"
  exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

cat > "$work/cert.cnf" <<EOF
[req]
distinguished_name = dn
prompt = no
x509_extensions = ext
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$work/key.pem" -out "$work/cert.pem" -config "$work/cert.cnf" 2>/dev/null

# PKCS#12 with a throwaway password; -legacy keeps it readable by `security` when the
# openssl in PATH is OpenSSL 3 (LibreSSL, the macOS default, does not know the flag).
p12_args=(-export -inkey "$work/key.pem" -in "$work/cert.pem" -out "$work/cert.p12" -passout pass:mgestures)
if openssl pkcs12 -help 2>&1 | grep -q -- '-legacy'; then p12_args+=(-legacy); fi
openssl pkcs12 "${p12_args[@]}"

if [[ ! -f "$KEYCHAIN" ]]; then
  security create-keychain -p "" "$KEYCHAIN"
fi
security set-keychain-settings "$KEYCHAIN"   # no auto-lock
security unlock-keychain -p "" "$KEYCHAIN"
security import "$work/cert.p12" -k "$KEYCHAIN" -P mgestures -T /usr/bin/codesign
# Lets codesign use the key without a confirmation dialog.
security set-key-partition-list -S apple-tool:,apple: -s -k "" "$KEYCHAIN" >/dev/null

# codesign only finds identities in keychains on the search list; add ours, keeping the rest.
existing=()
while IFS= read -r line; do
  line="${line#"${line%%[![:space:]]*}"}"; line="${line%\"}"; line="${line#\"}"
  [[ -n "$line" ]] && existing+=("$line")
done < <(security list-keychains -d user)
if [[ " ${existing[*]} " != *" $KEYCHAIN "* ]]; then
  security list-keychains -d user -s "${existing[@]}" "$KEYCHAIN"
fi

echo "Created \"$NAME\" in $KEYCHAIN"
echo "Rebuild with scripts/build-app.sh, then grant Accessibility once more; later rebuilds keep it."
