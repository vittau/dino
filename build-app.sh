#!/usr/bin/env bash
# Builds Dino.app into ./build. SwiftPM produces a bare binary, so the
# bundle (Info.plist, sprites, icon) is assembled by hand here.
#
#   ./build-app.sh          release build
#   ./build-app.sh debug    debug build
#   ./build-app.sh release --run
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${1:-release}"
RUN="${2:-}"
APP_NAME="Dino"
APP="build/${APP_NAME}.app"
BUNDLE_ID="com.vitor.dino"

echo "==> compiling ($CONFIG)"
swift build -c "$CONFIG"
BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)"

echo "==> assembling $APP"
rm -rf "$APP"
rm -rf "build/DinoWidget.app"   # leftover from before the rename
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/sprites"
cp "$BIN_PATH/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

if [ -d Resources/sprites ]; then
  cp Resources/sprites/*.png "$APP/Contents/Resources/sprites/" 2>/dev/null || true
  SPRITE_COUNT=$(ls -1 "$APP/Contents/Resources/sprites" | wc -l | tr -d ' ')
  echo "    bundled $SPRITE_COUNT sprites"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key><string>Dino</string>
  <key>CFBundleExecutable</key><string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.entertainment</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>Para você ditar suas mensagens para o Dino.</string>
  <key>NSHumanReadableCopyright</key><string>Um dinossaurinho fofo.</string>
</dict>
</plist>
PLIST

# Icon from the idle pose. iconutil needs the exact names below.
if [ -f Resources/sprites/idle_1.png ]; then
  ICONSET="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for spec in "16:16x16" "32:16x16@2x" "32:32x32" "64:32x32@2x" \
              "128:128x128" "256:128x128@2x" "256:256x256" "512:256x256@2x" \
              "512:512x512" "1024:512x512@2x"; do
    px="${spec%%:*}"; name="${spec##*:}"
    sips -z "$px" "$px" Resources/sprites/idle_1.png \
         --out "$ICONSET/icon_${name}.png" >/dev/null 2>&1
  done
  if iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null; then
    echo "    built AppIcon.icns"
  fi
  rm -rf "$(dirname "$ICONSET")"
fi

# Ad-hoc signature: enough for the file-access and network permissions the
# widget needs, without a developer certificate.
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 \
  && echo "    ad-hoc signed" || echo "    (codesign skipped)"

echo "==> done: $APP"

if [ "$RUN" = "--run" ]; then
  echo "==> launching"
  pkill -x "$APP_NAME" 2>/dev/null || true
  sleep 0.4
  open "$APP"
fi
