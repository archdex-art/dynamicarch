#!/bin/bash
# Creates a self-signed code signing identity so rebuilt copies of DynamicArch
# keep their TCC permissions (camera, calendar, location) instead of prompting
# again on every build. Run once; the certificate lives in your login keychain.
set -euo pipefail

NAME="DynamicArch Developer"

if security find-identity -v -p codesigning | grep -q "$NAME"; then
    echo "Identity '$NAME' already exists."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/config.cnf" <<EOF
[ req ]
distinguished_name = dn
prompt = no
x509_extensions = ext

[ dn ]
CN = $NAME

[ ext ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/config.cnf" >/dev/null 2>&1

openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/identity.p12" -passout pass: >/dev/null 2>&1

security import "$TMP/identity.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
    -P "" -T /usr/bin/codesign -T /usr/bin/security

# Trust it for code signing so codesign will use it without prompting.
security add-trusted-cert -d -r trustAsRoot -p codeSign \
    -k "$HOME/Library/Keychains/login.keychain-db" "$TMP/cert.pem" 2>/dev/null || \
    echo "Note: could not mark the certificate as trusted automatically; codesign may prompt once."

echo "Created code signing identity '$NAME'."
