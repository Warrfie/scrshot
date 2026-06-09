#!/bin/zsh
set -euo pipefail

PROJECT_PATH="${PROJECT_PATH:-scrshot.xcodeproj}"
SCHEME="${SCHEME:-scrshot}"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$PWD/.deriveddata-appstore}"
OUTPUT_DIR="${OUTPUT_DIR:-$PWD/build/appstore}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$OUTPUT_DIR/scrshot.xcarchive}"
EXPORT_PATH="${EXPORT_PATH:-$OUTPUT_DIR/export}"
EXPORT_OPTIONS_PLIST="${EXPORT_OPTIONS_PLIST:-$PWD/Config/AppStoreExportOptions.plist}"
DEVELOPMENT_TEAM_VALUE="${DEVELOPMENT_TEAM_VALUE:-}"
APPSTORE_SIGNING_STYLE="${APPSTORE_SIGNING_STYLE:-Automatic}"
CODE_SIGN_IDENTITY_VALUE="${CODE_SIGN_IDENTITY_VALUE:-Apple Distribution}"
MARKETING_VERSION_VALUE="${MARKETING_VERSION_VALUE:-}"
BUILD_NUMBER_VALUE="${BUILD_NUMBER_VALUE:-}"
APPSTORE_ALLOW_PROVISIONING_UPDATES="${APPSTORE_ALLOW_PROVISIONING_UPDATES:-NO}"
ASC_API_KEY_PATH="${ASC_API_KEY_PATH:-}"
ASC_API_KEY_ID="${ASC_API_KEY_ID:-}"
ASC_API_ISSUER_ID="${ASC_API_ISSUER_ID:-}"

ARCHIVE_ARGS=(
  -project "$PROJECT_PATH"
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -archivePath "$ARCHIVE_PATH"
  -derivedDataPath "$DERIVED_DATA_PATH"
  CODE_SIGNING_ALLOWED=YES
  CODE_SIGNING_REQUIRED=YES
  CODE_SIGN_STYLE="$APPSTORE_SIGNING_STYLE"
  CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY_VALUE"
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
  COMPILER_INDEX_STORE_ENABLE=NO
)

if [[ -n "$DEVELOPMENT_TEAM_VALUE" ]]; then
  ARCHIVE_ARGS+=(DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM_VALUE")
fi
if [[ -n "$MARKETING_VERSION_VALUE" ]]; then
  ARCHIVE_ARGS+=(MARKETING_VERSION="$MARKETING_VERSION_VALUE")
fi
if [[ -n "$BUILD_NUMBER_VALUE" ]]; then
  ARCHIVE_ARGS+=(CURRENT_PROJECT_VERSION="$BUILD_NUMBER_VALUE")
fi
if [[ "$APPSTORE_ALLOW_PROVISIONING_UPDATES" == "YES" ]]; then
  ARCHIVE_ARGS+=(-allowProvisioningUpdates)
fi
if [[ -n "$ASC_API_KEY_PATH" || -n "$ASC_API_KEY_ID" || -n "$ASC_API_ISSUER_ID" ]]; then
  : "${ASC_API_KEY_PATH:?Set ASC_API_KEY_PATH when using App Store Connect API signing authentication}"
  : "${ASC_API_KEY_ID:?Set ASC_API_KEY_ID when using App Store Connect API signing authentication}"
  : "${ASC_API_ISSUER_ID:?Set ASC_API_ISSUER_ID when using App Store Connect API signing authentication}"
  ARCHIVE_ARGS+=(
    -authenticationKeyPath "$ASC_API_KEY_PATH"
    -authenticationKeyID "$ASC_API_KEY_ID"
    -authenticationKeyIssuerID "$ASC_API_ISSUER_ID"
  )
fi

EXPORT_ARGS=(
  -exportArchive
  -archivePath "$ARCHIVE_PATH"
  -exportPath "$EXPORT_PATH"
  -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"
)

if [[ "$APPSTORE_ALLOW_PROVISIONING_UPDATES" == "YES" ]]; then
  EXPORT_ARGS+=(-allowProvisioningUpdates)
fi
if [[ -n "$ASC_API_KEY_PATH" ]]; then
  EXPORT_ARGS+=(
    -authenticationKeyPath "$ASC_API_KEY_PATH"
    -authenticationKeyID "$ASC_API_KEY_ID"
    -authenticationKeyIssuerID "$ASC_API_ISSUER_ID"
  )
fi

rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"
mkdir -p "$OUTPUT_DIR"

echo "Archiving $SCHEME for App Store Connect..."
xcodebuild archive "${ARCHIVE_ARGS[@]}" -destination 'generic/platform=macOS'

echo "Exporting App Store Connect package..."
xcodebuild "${EXPORT_ARGS[@]}"

echo
echo "Created App Store export:"
echo "  $ARCHIVE_PATH"
echo "  $EXPORT_PATH"
