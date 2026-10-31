#!/usr/bin/env bash
# Creates the signing files the TestFlight workflow needs, without a Mac.
# Run in Git Bash (Windows) or Terminal (macOS):
#
#   bash signing/make-signing-files.sh csr       # 1. private key + certificate request
#   bash signing/make-signing-files.sh p12       # 2. after downloading the .cer from Apple
#   bash signing/make-signing-files.sh profile   # 3. after downloading the .mobileprovision
#
# Everything is written to ~/encore-signing — OUTSIDE the repo. Never commit these files:
# the repo is public and the private key lets anyone sign apps as you.
set -euo pipefail
export MSYS_NO_PATHCONV=1 # stop Git Bash from mangling "/CN=..." into a Windows path

DIR="${ENCORE_SIGNING_DIR:-$HOME/encore-signing}"
mkdir -p "$DIR"
cd "$DIR"

b64() { openssl base64 -A -in "$1"; }

case "${1:-}" in
  csr)
    if [ -f distribution.key ]; then
      echo "distribution.key already exists in $DIR — delete it first if you really want a new one."
      exit 1
    fi
    openssl genrsa -out distribution.key 2048
    openssl req -new -key distribution.key -out distribution.csr -subj "/CN=Encore Distribution/C=US"
    cat <<EOF

Created $DIR/distribution.csr

Next:
  1. Open https://developer.apple.com/account/resources/certificates/add
  2. Choose "Apple Distribution", upload distribution.csr, download the certificate.
  3. Save the downloaded .cer file into $DIR
  4. Run: bash signing/make-signing-files.sh p12
EOF
    ;;

  p12)
    [ -f distribution.key ] || { echo "Run the 'csr' step first."; exit 1; }
    CER=$(ls -t *.cer 2>/dev/null | head -1 || true)
    [ -n "$CER" ] || { echo "Put the .cer downloaded from Apple into $DIR first."; exit 1; }
    openssl x509 -inform DER -in "$CER" -out distribution.pem 2>/dev/null \
      || openssl x509 -in "$CER" -out distribution.pem
    PASSWORD=$(openssl rand -hex 16)
    # 3DES/SHA1 so macOS `security import` on the build machine can read it.
    openssl pkcs12 -export -inkey distribution.key -in distribution.pem -out distribution.p12 \
      -name "Apple Distribution" -passout "pass:$PASSWORD" \
      -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1
    b64 distribution.p12 > IOS_DIST_CERT_P12_BASE64.txt
    printf '%s' "$PASSWORD" > IOS_DIST_CERT_PASSWORD.txt
    cat <<EOF

Created in $DIR:
  IOS_DIST_CERT_P12_BASE64.txt  -> paste into secret IOS_DIST_CERT_P12_BASE64
  IOS_DIST_CERT_PASSWORD.txt    -> paste into secret IOS_DIST_CERT_PASSWORD

Next: create the App Store provisioning profile (see README), save the
.mobileprovision into $DIR, then run: bash signing/make-signing-files.sh profile
EOF
    ;;

  profile)
    PROFILE=$(ls -t *.mobileprovision 2>/dev/null | head -1 || true)
    [ -n "$PROFILE" ] || { echo "Put the .mobileprovision downloaded from Apple into $DIR first."; exit 1; }
    b64 "$PROFILE" > IOS_PROVISIONING_PROFILE_BASE64.txt
    cat <<EOF

Created $DIR/IOS_PROVISIONING_PROFILE_BASE64.txt
  -> paste into secret IOS_PROVISIONING_PROFILE_BASE64
EOF
    ;;

  *)
    sed -n '2,9p' "$0"
    exit 1
    ;;
esac
