#!/usr/bin/env bash
# scripts/create-dev-cert.sh
# Creates a self-signed code-signing certificate named "OpenTab Dev" in the
# login keychain so macOS keeps the Accessibility grant across rebuilds.
set -euo pipefail

CERT_NAME="OpenTab Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "$CERT_NAME"; then
  echo "Certificate \"$CERT_NAME\" already exists. Nothing to do."
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cfg" <<CFG
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = $CERT_NAME
[ ext ]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
CFG

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.cfg" >/dev/null 2>&1

openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -out "$TMP/identity.p12" -passout pass: -name "$CERT_NAME" >/dev/null 2>&1

security import "$TMP/identity.p12" -k "$KEYCHAIN" -P "" \
  -T /usr/bin/codesign -T /usr/bin/security

# Allow codesign to use the key without an interactive prompt on each build.
security set-key-partition-list -S apple-tool:,apple: -k "" "$KEYCHAIN" >/dev/null 2>&1 || true

echo "Created code-signing certificate \"$CERT_NAME\"."
echo "Now run: make run   (grant Accessibility once; it will persist afterwards)"
