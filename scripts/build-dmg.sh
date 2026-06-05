#!/bin/zsh
set -euo pipefail

PROJECT_PATH="${PROJECT_PATH:-scrshot.xcodeproj}"
SCHEME="${SCHEME:-scrshot}"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$PWD/.deriveddata-release}"
OUTPUT_DIR="${OUTPUT_DIR:-$PWD/build/artifacts}"
APP_NAME="${APP_NAME:-scrshot.app}"
DMG_BASENAME="${DMG_BASENAME:-scrshot-macos}"
VOLUME_NAME="${VOLUME_NAME:-scrshot}"
SIGNING_ALLOWED="${SIGNING_ALLOWED:-NO}"
NOTARIZATION_ALLOWED="${NOTARIZATION_ALLOWED:-NO}"
CODE_SIGN_IDENTITY_VALUE="${CODE_SIGN_IDENTITY_VALUE:-}"
DEVELOPMENT_TEAM_VALUE="${DEVELOPMENT_TEAM_VALUE:-}"
DMG_CODE_SIGN_IDENTITY="${DMG_CODE_SIGN_IDENTITY:-$CODE_SIGN_IDENTITY_VALUE}"
ASC_API_KEY_ID="${ASC_API_KEY_ID:-}"
ASC_API_ISSUER_ID="${ASC_API_ISSUER_ID:-}"
ASC_API_KEY_P8_BASE64="${ASC_API_KEY_P8_BASE64:-}"
KEYCHAIN_PATH="${KEYCHAIN_PATH:-}"

APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME"
STAGING_DIR="$OUTPUT_DIR/dmg-root"
DMG_PATH="$OUTPUT_DIR/$DMG_BASENAME.dmg"
SHA_PATH="$OUTPUT_DIR/$DMG_BASENAME.sha256"
NOTARY_RESULT_PATH="$OUTPUT_DIR/$DMG_BASENAME.notary.json"
NOTARY_KEY_PATH=""

cleanup() {
  if [[ -n "$NOTARY_KEY_PATH" ]]; then
    rm -f "$NOTARY_KEY_PATH"
  fi
}
trap cleanup EXIT

SIGNING_ARGS=(
  CODE_SIGNING_ALLOWED="$SIGNING_ALLOWED"
  COMPILER_INDEX_STORE_ENABLE=NO
)

if [[ "$SIGNING_ALLOWED" == "YES" ]]; then
  resolve_developer_id_identity() {
    if [[ -z "$KEYCHAIN_PATH" ]]; then
      echo "KEYCHAIN_PATH is required when code signing identity is AUTO" >&2
      exit 1
    fi
    security find-identity -v -p codesigning "$KEYCHAIN_PATH" \
      | sed -n 's/.*"\(Developer ID Application: .*\)".*/\1/p' \
      | head -n 1
  }

  if [[ -z "$CODE_SIGN_IDENTITY_VALUE" || "$CODE_SIGN_IDENTITY_VALUE" == "AUTO" ]]; then
    CODE_SIGN_IDENTITY_VALUE="$(resolve_developer_id_identity)"
  fi
  if [[ -z "$DMG_CODE_SIGN_IDENTITY" || "$DMG_CODE_SIGN_IDENTITY" == "AUTO" ]]; then
    DMG_CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY_VALUE"
  fi
  : "${CODE_SIGN_IDENTITY_VALUE:?Set CODE_SIGN_IDENTITY_VALUE for signed builds}"
  : "${DEVELOPMENT_TEAM_VALUE:?Set DEVELOPMENT_TEAM_VALUE for signed builds}"
  SIGNING_ARGS+=(
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
    CODE_SIGNING_REQUIRED=YES
    CODE_SIGN_STYLE=Manual
    CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY_VALUE"
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM_VALUE"
  )
  if [[ -n "$KEYCHAIN_PATH" ]]; then
    SIGNING_ARGS+=(
      OTHER_CODE_SIGN_FLAGS="--keychain $KEYCHAIN_PATH --timestamp"
    )
  else
    SIGNING_ARGS+=(
      OTHER_CODE_SIGN_FLAGS="--timestamp"
    )
  fi
else
  SIGNING_ARGS+=(
    CODE_SIGNING_REQUIRED=NO
    CODE_SIGN_IDENTITY=""
    DEVELOPMENT_TEAM=""
  )
fi

echo "Building $APP_NAME from scheme '$SCHEME'..."
xcodebuild build \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  "${SIGNING_ARGS[@]}" \
  -destination 'platform=macOS'

if [[ ! -d "$APP_PATH" ]]; then
  echo "Expected app bundle not found at $APP_PATH" >&2
  exit 1
fi

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
mkdir -p "$OUTPUT_DIR"

ditto "$APP_PATH" "$STAGING_DIR/$APP_NAME"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DMG_PATH" "$SHA_PATH" "$NOTARY_RESULT_PATH"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

if [[ "$SIGNING_ALLOWED" == "YES" && -n "$DMG_CODE_SIGN_IDENTITY" ]]; then
  DMG_CODESIGN_ARGS=(
    --force
    --timestamp
    --sign "$DMG_CODE_SIGN_IDENTITY"
  )
  if [[ -n "$KEYCHAIN_PATH" ]]; then
    DMG_CODESIGN_ARGS+=(--keychain "$KEYCHAIN_PATH")
  fi
  codesign "${DMG_CODESIGN_ARGS[@]}" "$DMG_PATH"
fi

if [[ "$NOTARIZATION_ALLOWED" == "YES" ]]; then
  if [[ "$SIGNING_ALLOWED" != "YES" ]]; then
    echo "NOTARIZATION_ALLOWED=YES requires SIGNING_ALLOWED=YES" >&2
    exit 1
  fi
  : "${ASC_API_KEY_ID:?Set ASC_API_KEY_ID for notarization}"
  : "${ASC_API_ISSUER_ID:?Set ASC_API_ISSUER_ID for notarization}"
  : "${ASC_API_KEY_P8_BASE64:?Set ASC_API_KEY_P8_BASE64 for notarization}"

  umask 077
  NOTARY_KEY_PATH="$(mktemp "${TMPDIR:-/tmp}/scrshot-notary-key.XXXXXX")"
  printf '%s' "$ASC_API_KEY_P8_BASE64" | base64 --decode > "$NOTARY_KEY_PATH"

  xcrun notarytool submit "$DMG_PATH" \
    --key "$NOTARY_KEY_PATH" \
    --key-id "$ASC_API_KEY_ID" \
    --issuer "$ASC_API_ISSUER_ID" \
    --wait \
    --output-format json \
    | tee "$NOTARY_RESULT_PATH"

  NOTARY_STATUS="$(/usr/bin/plutil -extract status raw -o - "$NOTARY_RESULT_PATH")"
  NOTARY_ID="$(/usr/bin/plutil -extract id raw -o - "$NOTARY_RESULT_PATH")"

  if [[ "$NOTARY_STATUS" != "Accepted" ]]; then
    echo "Notarization failed with status: $NOTARY_STATUS" >&2
    if [[ -n "$NOTARY_ID" ]]; then
      xcrun notarytool log "$NOTARY_ID" \
        --key "$NOTARY_KEY_PATH" \
        --key-id "$ASC_API_KEY_ID" \
        --issuer "$ASC_API_ISSUER_ID" || true
    fi
    exit 1
  fi

  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
  spctl --assess --type open --verbose "$DMG_PATH"
fi

shasum -a 256 "$DMG_PATH" > "$SHA_PATH"

echo
echo "Created artifacts:"
echo "  $DMG_PATH"
echo "  $SHA_PATH"
