#!/usr/bin/env bash
# Creates (idempotently) a stable self-signed code-signing identity for Gridlet.
#
# Why: ad-hoc signing (`codesign -s -`) produces a new cdhash on every build, so macOS
# drops Gridlet's Accessibility grant each time and it has to be re-enabled by hand.
# A certificate-based identity keeps the same designated requirement across rebuilds, so
# the grant sticks.
#
# The identity lives in its own keychain with a throwaway password so signing is
# non-interactive. It is NOT added to the system trust settings: it exists only to give
# builds a stable code identity.
set -euo pipefail

KEYCHAIN="${GRIDLET_KEYCHAIN:-$HOME/Library/Keychains/gridlet-dev.keychain-db}"
KEYCHAIN_PASSWORD="${GRIDLET_KEYCHAIN_PASSWORD:-gridlet-dev}"
IDENTITY="${GRIDLET_SIGN_IDENTITY:-Gridlet Dev}"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

if security find-certificate -c "$IDENTITY" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "$IDENTITY"
  exit 0
fi

echo "==> creating code-signing identity '$IDENTITY' in $KEYCHAIN" >&2

if [ ! -f "$KEYCHAIN" ]; then
  security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
fi
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"

OPENSSL=/usr/bin/openssl
"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$WORKDIR/key.pem" -out "$WORKDIR/cert.pem" \
  -subj "/CN=$IDENTITY/O=Gridlet Development" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null

"$OPENSSL" pkcs12 -export -out "$WORKDIR/identity.p12" \
  -inkey "$WORKDIR/key.pem" -in "$WORKDIR/cert.pem" \
  -name "$IDENTITY" -passout pass:"$KEYCHAIN_PASSWORD" 2>/dev/null

security import "$WORKDIR/identity.p12" -k "$KEYCHAIN" -P "$KEYCHAIN_PASSWORD" \
  -T /usr/bin/codesign -A >/dev/null
# Allow codesign to use the private key without prompting for the keychain password.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null

security find-certificate -c "$IDENTITY" "$KEYCHAIN" >/dev/null
echo "$IDENTITY"
