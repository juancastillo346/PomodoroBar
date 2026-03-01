#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
EXECUTABLE_NAME="FocusTimer"
APP_BUNDLE_NAME="FocusTimer"
APP_DISPLAY_NAME="Focus Timer"
BUNDLE_ID="com.juancastillo.focustimer"
BUILD_CONFIG="release"
BUILD_DIR="$ROOT_DIR/.build/$BUILD_CONFIG"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_BUNDLE_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$ROOT_DIR"

# Keep compiler/package caches inside the repo so builds work in restricted environments.
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/swiftpm-module-cache"
export SWIFTPM_TESTS_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/swiftpm-tests-module-cache"
swift build --disable-sandbox -c "$BUILD_CONFIG"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BUILD_DIR/$EXECUTABLE_NAME" "$MACOS_DIR/$EXECUTABLE_NAME"
chmod +x "$MACOS_DIR/$EXECUTABLE_NAME"

ICON_SOURCE="$ROOT_DIR/assets/AppIcon.png"
ICON_ICNS="$ROOT_DIR/assets/AppIcon.icns"
ICON_FILL_RATIO="${ICON_FILL_RATIO:-0.64}"
if [[ -f "$ICON_SOURCE" ]]; then
  if python3 "$ROOT_DIR/scripts/make_icns.py" "$ICON_SOURCE" "$ICON_ICNS" "$ICON_FILL_RATIO"; then
    cp "$ICON_ICNS" "$RESOURCES_DIR/AppIcon.icns"
  else
    echo "warning: icon conversion failed; keeping previous app icon if available."
  fi
fi

cat > "$CONTENTS_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$EXECUTABLE_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundleName</key>
  <string>$APP_BUNDLE_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <false/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
EOF

if [[ -f "$RESOURCES_DIR/AppIcon.icns" ]]; then
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$CONTENTS_DIR/Info.plist" >/dev/null
fi

# Ad-hoc sign so macOS consistently treats this as an application bundle.
codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo "Built app bundle:"
echo "$APP_DIR"
