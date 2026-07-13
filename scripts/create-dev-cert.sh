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

# System LibreSSL produces PKCS#12 files macOS `security` can import; Homebrew
# OpenSSL 3 defaults to a MAC algorithm the keychain rejects.
OPENSSL=/usr/bin/openssl
[ -x "$OPENSSL" ] || OPENSSL=openssl
P12_PASS=opentab

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

"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.cfg" >/dev/null 2>&1

"$OPENSSL" pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -out "$TMP/identity.p12" -passout "pass:$P12_PASS" -name "$CERT_NAME" >/dev/null 2>&1

security import "$TMP/identity.p12" -k "$KEYCHAIN" -P "$P12_PASS" \
  -T /usr/bin/codesign -T /usr/bin/security

echo "Created code-signing certificate \"$CERT_NAME\"."
echo "Now run: make run   (grant Accessibility once; it will persist afterwards)"
echo "codesign may prompt once to use the key — click \"Always Allow\"."
