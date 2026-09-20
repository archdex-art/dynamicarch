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

openssl req -x509 -newkey rsa:2048 -nodes -days 825 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/config.cnf" >/dev/null 2>&1

# A one-time random passphrase, not an empty one. It only has to survive
# the few milliseconds between export and import, and never touches disk in
# readable form - but an empty-password PKCS#12 sitting in a temp directory is
# a needless window for anything watching that directory.
PASSPHRASE="$(openssl rand -hex 24)"

# -legacy: OpenSSL 3 defaults to AES-256-CBC with a SHA-256 MAC, which Apple's
# SecKeychainItemImport rejects outright ("MAC verification failed"). The
# legacy PBE algorithms are what the Security framework can read.
openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/identity.p12" -passout "pass:$PASSPHRASE" >/dev/null 2>&1

# Only codesign may use the key without a prompt. Granting /usr/bin/security
# access as well would let any process running as the user export the private
# key silently - and because TCC binds the app's grants to this identity,
# stealing it means signing a hostile binary that inherits Accessibility,
# Camera and Location approvals.
security import "$TMP/identity.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
    -P "$PASSPHRASE" -T /usr/bin/codesign
unset PASSPHRASE

# Note: the certificate is deliberately NOT added as a trusted code-signing
# root. codesign does not need the certificate to be trusted in order to sign;
# only verification does, and trusting a 10-year self-signed CA for code
# signing weakens every other signature check on the machine.

echo "Created code signing identity '$NAME'."
echo "It is usable by codesign only, and is not trusted as a signing root."
echo "Verify local builds with: codesign --verify --no-strict build/DynamicArch.app"
