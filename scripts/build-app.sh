#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Waid"
APP_VERSION="$(sed -nE 's/^[[:space:]]*"version":[[:space:]]*"([^"]+)".*/\1/p' "$ROOT_DIR/package.json" | head -n 1)"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"
WEB_DIR="$RESOURCES_DIR/web"
MODULE_CACHE_DIR="$ROOT_DIR/.build/module-cache"
ICON_SOURCE="$ROOT_DIR/public/favicon.png"
TRIMMED_ICON_SOURCE="$ROOT_DIR/.build/$APP_NAME-icon-trimmed.png"
ICON_RENDER_SOURCE="$ROOT_DIR/.build/$APP_NAME-icon-render.png"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"

if [[ -z "$APP_VERSION" ]]; then
  APP_VERSION="0.1.0"
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Waid.app can only be built on macOS."
  exit 1
fi

if ! command -v swiftc >/dev/null 2>&1; then
  echo "swiftc was not found."
  echo "Install Apple's Command Line Tools with: xcode-select --install"
  exit 1
fi

if ! command -v sips >/dev/null 2>&1; then
  echo "Building the app icon requires sips."
  exit 1
fi

if [[ ! -f "$ICON_SOURCE" ]]; then
  echo "Missing app icon source: $ICON_SOURCE"
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$WEB_DIR" "$MODULE_CACHE_DIR"

cp -R "$ROOT_DIR/public/." "$WEB_DIR"
SWIFT_MODULECACHE_PATH="$MODULE_CACHE_DIR" \
CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR" \
xcrun swift "$ROOT_DIR/scripts/trim-icon.swift" "$ICON_SOURCE" "$TRIMMED_ICON_SOURCE"
sips -z 512 512 "$TRIMMED_ICON_SOURCE" --out "$ICON_RENDER_SOURCE" >/dev/null
sips -s format icns "$ICON_RENDER_SOURCE" --out "$RESOURCES_DIR/$APP_NAME.icns" >/dev/null

cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>
    <string>Waid</string>
    <key>CFBundleIconFile</key>
    <string>$APP_NAME.icns</string>
    <key>CFBundleIdentifier</key>
    <string>local.waid.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Waid</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$APP_VERSION</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
  </dict>
</plist>
EOF

SWIFT_MODULECACHE_PATH="$MODULE_CACHE_DIR" \
CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR" \
xcrun swiftc \
  -O \
  -sdk "$SDK_PATH" \
  -framework AppKit \
  -framework WebKit \
  "$ROOT_DIR/app/Sources/main.swift" \
  "$ROOT_DIR/app/Sources/AppDelegate.swift" \
  "$ROOT_DIR/app/Sources/WebBridgeController.swift" \
  "$ROOT_DIR/app/Sources/TrackingStore.swift" \
  -o "$MACOS_DIR/$APP_NAME"

chmod +x "$MACOS_DIR/$APP_NAME"

echo "Built $APP_DIR"
