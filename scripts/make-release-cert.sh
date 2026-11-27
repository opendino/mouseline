#!/usr/bin/env bash
# Creates the self-signed certificate that GitHub Actions signs releases with.
#
#   scripts/make-release-cert.sh                 # create it in ~/.mouseline-release-signing
#   scripts/make-release-cert.sh --set-secrets   # also store it as repository secrets (gh)
#
# Why: an ad-hoc signature changes with every build, and macOS ties the Accessibility
# permission to the signature, so every update would make users grant it again. Releases
# signed with one fixed certificate keep the same designated requirement
# (identifier "app.mouseline" and certificate leaf = …), so the permission survives updates.
#
# It does NOT remove the Gatekeeper warning: only a Developer ID certificate and
# notarization do that. The certificate is not trusted by anyone, and doesn't need to be.
#
# Outputs, in $OUT_DIR (default ~/.mouseline-release-signing, readable only by you):
#   release-signing.p12        certificate and private key
#   release-signing.password   the .p12 password
# Keep a copy of both somewhere safe (a password manager): if they are lost, the next
# release gets a new signature and every user has to grant Accessibility once more.
# Anyone who has them can sign an app that macOS treats as MouseLine for permissions,
# so never commit them.
#
# --set-secrets stores them in the GitHub repository as RELEASE_SIGNING_P12 (base64) and
# RELEASE_SIGNING_P12_PASSWORD, which .github/workflows/release.yml uses.
set -euo pipefail

cd "$(dirname "$0")/.."

NAME="MouseLine Release Signing"
OUT_DIR="${OUT_DIR:-$HOME/.mouseline-release-signing}"
P12="$OUT_DIR/release-signing.p12"
PASSWORD_FILE="$OUT_DIR/release-signing.password"

# OpenSSL 3+ needs -legacy to write and read the PKCS#12 format `security import` accepts;
# LibreSSL, the macOS default, does not know the flag and uses that format anyway.
legacy=()
if openssl pkcs12 -help 2>&1 | grep -q -- '-legacy'; then legacy=(-legacy); fi

set_secrets=false
for arg in "$@"; do
  case "$arg" in
    --set-secrets) set_secrets=true ;;
    *) echo "usage: $0 [--set-secrets]" >&2; exit 2 ;;
  esac
done

if [[ -f "$P12" ]]; then
  echo "Keeping the existing certificate in $P12 (delete it first to make a new one)."
else
  mkdir -p "$OUT_DIR"
  chmod 700 "$OUT_DIR"
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

  # 20 years: the certificate is pinned by hash, so it should outlive the project.
  openssl req -x509 -newkey rsa:3072 -nodes -days 7300 \
    -keyout "$work/key.pem" -out "$work/cert.pem" -config "$work/cert.cnf" 2>/dev/null

  password="$(openssl rand -hex 24)"
  (umask 077; openssl pkcs12 -export ${legacy[@]+"${legacy[@]}"} -inkey "$work/key.pem" \
    -in "$work/cert.pem" -name "$NAME" -out "$P12" -passout "pass:$password")
  (umask 077; printf '%s\n' "$password" > "$PASSWORD_FILE")
  echo "Created \"$NAME\" in $P12"
fi

sha1="$(openssl pkcs12 ${legacy[@]+"${legacy[@]}"} -in "$P12" -passin "file:$PASSWORD_FILE" -nokeys \
  | openssl x509 -noout -fingerprint -sha1 | sed 's/.*=//; s/://g')"
echo "SHA-1: $sha1"

if $set_secrets; then
  base64 < "$P12" | gh secret set RELEASE_SIGNING_P12
  tr -d '\n' < "$PASSWORD_FILE" | gh secret set RELEASE_SIGNING_P12_PASSWORD
  echo "Stored RELEASE_SIGNING_P12 and RELEASE_SIGNING_P12_PASSWORD in the repository secrets."
else
  echo "Store it for GitHub Actions with: $0 --set-secrets"
fi
echo "Back up $OUT_DIR (for example in your password manager)."
