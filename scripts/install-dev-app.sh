#!/bin/zsh
set -euo pipefail

APP_NAME="scrshot-dev.app"
DEST_APP="$HOME/Applications/$APP_NAME"

find_source_app() {
  local provided_path="${1:-}"
  if [[ -n "$provided_path" ]]; then
    echo "$provided_path"
    return 0
  fi

  local derived_data_root="$HOME/Library/Developer/Xcode/DerivedData"
  local source_app
  source_app=$(find "$derived_data_root" -path "*/Build/Products/Debug/scrshot.app" -type d -print 2>/dev/null | xargs ls -td 2>/dev/null | head -n 1 || true)
  if [[ -z "$source_app" ]]; then
    echo "Unable to find a Debug scrshot.app in DerivedData." >&2
    echo "Build the app in Xcode first, or pass the app path as the first argument." >&2
    exit 1
  fi

  echo "$source_app"
}

sign_app() {
  local app_path="$1"
  local identity
  identity=$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Apple Development:.*\)"/\1/p' | head -n 1 || true)

  if [[ -n "$identity" ]]; then
    echo "Signing $app_path with Apple Development identity: $identity"
    codesign --force --deep --sign "$identity" --timestamp=none "$app_path"
  else
    echo "No Apple Development identity found. Falling back to ad hoc signing." >&2
    codesign --force --deep --sign - --timestamp=none "$app_path"
  fi
}

main() {
  local source_app
  source_app=$(find_source_app "${1:-}")

  mkdir -p "$HOME/Applications"
  rm -rf "$DEST_APP"
  ditto "$source_app" "$DEST_APP"
  sign_app "$DEST_APP"

  echo
  echo "Installed stable dev app at:"
  echo "  $DEST_APP"
  echo
  echo "Next steps:"
  echo "  1. Open $DEST_APP once."
  echo "  2. Re-grant Screen Recording and Microphone permissions for scrshot-dev if macOS asks."
  echo "  3. Use this app for development runs instead of launching directly from DerivedData."
}

main "$@"
