#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Waid"
APP_VERSION="$(sed -nE 's/^[[:space:]]*"version":[[:space:]]*"([^"]+)".*/\1/p' "$ROOT_DIR/package.json" | head -n 1)"
DIST_DIR="$ROOT_DIR/dist"
APP_PATH="$DIST_DIR/$APP_NAME.app"
TMP_DIR="$ROOT_DIR/.build/release"

if [[ -z "$APP_VERSION" ]]; then
  APP_VERSION="0.1.0"
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Release packaging is only supported on macOS."
  exit 1
fi

if ! command -v ditto >/dev/null 2>&1; then
  echo "ditto was not found."
  exit 1
fi

if ! command -v hdiutil >/dev/null 2>&1; then
  echo "hdiutil was not found."
  exit 1
fi

case "$(uname -m)" in
  arm64)
    ARCH_LABEL="apple-silicon"
    ;;
  x86_64)
    ARCH_LABEL="intel"
    ;;
  *)
    ARCH_LABEL="$(uname -m)"
    ;;
esac

ARTIFACT_BASENAME="$APP_NAME-$APP_VERSION-macos-$ARCH_LABEL"
ZIP_PATH="$DIST_DIR/$ARTIFACT_BASENAME.zip"
DMG_PATH="$DIST_DIR/$ARTIFACT_BASENAME.dmg"
DMG_STAGING_DIR="$TMP_DIR/dmg/$APP_NAME"

"$ROOT_DIR/scripts/build-app.sh"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Expected app bundle was not created: $APP_PATH"
  exit 1
fi

rm -f "$ZIP_PATH" "$DMG_PATH"
rm -rf "$DMG_STAGING_DIR"
mkdir -p "$DMG_STAGING_DIR"

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

cp -R "$APP_PATH" "$DMG_STAGING_DIR/"
ln -sfn /Applications "$DMG_STAGING_DIR/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

echo "Built $ZIP_PATH"
echo "Built $DMG_PATH"
