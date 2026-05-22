#!/bin/bash
set -euo pipefail

APP="QueueDo"
DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD="$DIR/build"
APP_BUNDLE="$BUILD/$APP.app"
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"
RES_DIR="$APP_BUNDLE/Contents/Resources"

rm -rf "$BUILD"
mkdir -p "$MACOS_DIR" "$RES_DIR"

# Build app icon (.icns) from QUEUE.png if present
ICON_SRC="$DIR/QUEUE.png"
if [ -f "$ICON_SRC" ]; then
  ICONSET="$BUILD/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for pair in "16 icon_16x16.png" "32 icon_16x16@2x.png" \
              "32 icon_32x32.png" "64 icon_32x32@2x.png" \
              "128 icon_128x128.png" "256 icon_128x128@2x.png" \
              "256 icon_256x256.png" "512 icon_256x256@2x.png" \
              "512 icon_512x512.png" "1024 icon_512x512@2x.png"; do
    size=${pair% *}; name=${pair#* }
    sips -z "$size" "$size" "$ICON_SRC" --out "$ICONSET/$name" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$RES_DIR/AppIcon.icns"
  rm -rf "$ICONSET"
  ICON_KEY='<key>CFBundleIconFile</key><string>AppIcon</string>'
else
  ICON_KEY=''
fi

cat > "$APP_BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>QueueDo</string>
  <key>CFBundleDisplayName</key><string>QueueDo</string>
  <key>CFBundleIdentifier</key><string>com.local.queuedo</string>
  <key>CFBundleExecutable</key><string>QueueDo</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSCalendarsUsageDescription</key><string>QueueDo creates calendar events for tasks with due dates.</string>
  <key>NSCalendarsFullAccessUsageDescription</key><string>QueueDo creates calendar events for tasks with due dates.</string>
  <key>NSRemindersUsageDescription</key><string>QueueDo creates reminders for your tasks.</string>
  <key>NSRemindersFullAccessUsageDescription</key><string>QueueDo creates reminders for your tasks.</string>
  ${ICON_KEY}
</dict>
</plist>
EOF

swiftc -O \
  -parse-as-library \
  -target arm64-apple-macos14 \
  -framework EventKit \
  -o "$MACOS_DIR/QueueDo" \
  "$DIR/Sources/main.swift"

# Ad-hoc sign so macOS treats it as a stable identity
codesign --force --sign - "$APP_BUNDLE" >/dev/null 2>&1 || true

# Install to /Applications so Spotlight / Launchpad find it
INSTALL_PATH="/Applications/$APP.app"
osascript -e "tell application \"$APP\" to quit" >/dev/null 2>&1 || true
pkill -f "$INSTALL_PATH" >/dev/null 2>&1 || true
sleep 0.5
rm -rf "$INSTALL_PATH"
ditto "$APP_BUNDLE" "$INSTALL_PATH"
codesign --force --sign - "$INSTALL_PATH" >/dev/null 2>&1 || true

echo "Built:     $APP_BUNDLE"
echo "Installed: $INSTALL_PATH"
