#!/bin/zsh
set -euo pipefail

: "${MACOS_CERTIFICATE_P12_BASE64:?Set MACOS_CERTIFICATE_P12_BASE64 in CI secrets}"
: "${MACOS_CERTIFICATE_PASSWORD:?Set MACOS_CERTIFICATE_PASSWORD in CI secrets}"

CI_TEMP_DIR="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
KEYCHAIN_PATH="${KEYCHAIN_PATH:-$CI_TEMP_DIR/scrshot-signing.keychain-db}"
KEYCHAIN_PASSWORD="${KEYCHAIN_PASSWORD:-$(uuidgen)}"
CERTIFICATE_PATH="${CERTIFICATE_PATH:-$CI_TEMP_DIR/scrshot-signing.p12}"
CODE_SIGN_IDENTITY_VALUE="${CODE_SIGN_IDENTITY_VALUE:-}"

umask 077
printf '%s' "$MACOS_CERTIFICATE_P12_BASE64" | base64 --decode > "$CERTIFICATE_PATH"

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security import "$CERTIFICATE_PATH" \
  -P "$MACOS_CERTIFICATE_PASSWORD" \
  -A \
  -t cert \
  -f pkcs12 \
  -k "$KEYCHAIN_PATH"
security list-keychains -d user -s "$KEYCHAIN_PATH" $(security list-keychains -d user | tr -d '"')
security default-keychain -d user -s "$KEYCHAIN_PATH"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

rm -f "$CERTIFICATE_PATH"

if [[ -n "$CODE_SIGN_IDENTITY_VALUE" ]]; then
  if ! security find-identity -v -p codesigning "$KEYCHAIN_PATH" | grep -F "$CODE_SIGN_IDENTITY_VALUE" > /dev/null; then
    echo "Expected code signing identity was not found in the temporary keychain." >&2
    echo "Check MACOS_CODE_SIGN_IDENTITY, MACOS_CERTIFICATE_P12_BASE64, and that the exported .p12 includes the private key." >&2
    exit 1
  fi
fi
