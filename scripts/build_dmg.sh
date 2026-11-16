#!/bin/zsh
# Builds Paster.app and dist/Paster-<version>.dmg (drag-to-Applications installer).
set -euo pipefail

VERSION="${VERSION:-1.0.0}"
ROOT="${0:A:h:h}"
cd "$ROOT"
BUILD="$ROOT/build"
DIST="$ROOT/dist"
APP="$BUILD/Paster.app"
rm -rf "$BUILD" && mkdir -p "$BUILD" "$DIST"

echo "==> Compiling (release)"
if swift build -c release --arch arm64 --arch x86_64 >/dev/null 2>&1; then
  BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Paster"
else
  swift build -c release
  BIN="$(swift build -c release --show-bin-path)/Paster"
fi

echo "==> Running self-tests"
PASTER_DATA_DIR="$BUILD/selftest" "$BIN" --self-test >/dev/null

echo "==> Assembling Paster.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Paster"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Paster</string>
  <key>CFBundleDisplayName</key><string>Paster</string>
  <key>CFBundleIdentifier</key><string>io.github.szjqsong.paster</string>
  <key>CFBundleExecutable</key><string>Paster</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticTermination</key><false/>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>zh-Hant</string><string>zh-Hans</string></array>
</dict>
</plist>
PLIST

echo "==> Generating icon"
ICONSET="$BUILD/AppIcon.iconset"
mkdir -p "$ICONSET"
swift "$ROOT/scripts/make_icon.swift" "$BUILD/icon-1024.png"
for s in 16 32 128 256 512; do
  sips -z $s $s "$BUILD/icon-1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$BUILD/icon-1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "==> Signing (ad-hoc)"
codesign --force --deep --options runtime --timestamp=none -s - "$APP"
codesign --verify --strict "$APP"

echo "==> Creating DMG"
STAGE="$BUILD/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
DMG="$DIST/Paster-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "Paster" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
echo "==> Done: $DMG"
