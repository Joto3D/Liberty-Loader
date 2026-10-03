#!/usr/bin/env bash
# Builds Liberty Loader and wraps the executable in a macOS .app bundle (and optionally a .dmg).
#   scripts/bundle.sh            -> build/Liberty Loader.app
#   scripts/bundle.sh --dmg      -> also build/LibertyLoader.dmg
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="${VERSION:-0.1.0}"
APP="build/Liberty Loader.app"

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/LibertyLoader"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/LibertyLoader"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Liberty Loader</string>
    <key>CFBundleDisplayName</key><string>Liberty Loader</string>
    <key>CFBundleIdentifier</key><string>com.joto3d.libertyloader</string>
    <key>CFBundleExecutable</key><string>LibertyLoader</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signature so Gatekeeper lets a local build run; release builds should use a Developer ID.
codesign --force --deep --sign "${SIGN_IDENTITY:--}" "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--dmg" ]]; then
  rm -f build/LibertyLoader.dmg
  hdiutil create -volname "Liberty Loader" -srcfolder "$APP" -ov -format UDZO build/LibertyLoader.dmg
  echo "Built build/LibertyLoader.dmg"
fi
