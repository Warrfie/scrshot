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

APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME"
STAGING_DIR="$OUTPUT_DIR/dmg-root"
DMG_PATH="$OUTPUT_DIR/$DMG_BASENAME.dmg"
SHA_PATH="$OUTPUT_DIR/$DMG_BASENAME.sha256"

echo "Building $APP_NAME from scheme '$SCHEME'..."
xcodebuild build \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  DEVELOPMENT_TEAM="" \
  COMPILER_INDEX_STORE_ENABLE=NO \
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

rm -f "$DMG_PATH" "$SHA_PATH"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

shasum -a 256 "$DMG_PATH" > "$SHA_PATH"

echo
echo "Created artifacts:"
echo "  $DMG_PATH"
echo "  $SHA_PATH"
