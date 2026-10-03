#!/usr/bin/env bash
# Builds Liberty Loader and wraps the executable in a macOS .app bundle (and optionally a .dmg).
#   scripts/bundle.sh            -> build/Liberty Loader.app
#   scripts/bundle.sh --dmg      -> also build/LibertyLoader.dmg and build/LibertyLoader.zip (used by in-app updates)
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="${VERSION:-0.1.0}"
APP="build/Liberty Loader.app"

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/LibertyLoader"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/LibertyLoader"
# Translations (English + German); macOS picks one based on the system language.
cp -R Localization/*.lproj "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Liberty Loader</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key><array><string>en</string><string>de</string></array>
    <key>CFBundleDisplayName</key><string>Liberty Loader</string>
    <key>CFBundleIdentifier</key><string>com.joto3d.libertyloader</string>
    <key>CFBundleExecutable</key><string>LibertyLoader</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key><string>Nexus Mods download</string>
            <key>CFBundleURLSchemes</key><array><string>nxm</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

# Ad-hoc signature so Gatekeeper lets a local build run; release builds should use a Developer ID.
codesign --force --deep --sign "${SIGN_IDENTITY:--}" "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--dmg" ]]; then
  rm -f build/LibertyLoader.dmg build/LibertyLoader.zip
  ditto -c -k --keepParent "$APP" build/LibertyLoader.zip
  hdiutil create -volname "Liberty Loader" -srcfolder "$APP" -ov -format UDZO build/LibertyLoader.dmg
  echo "Built build/LibertyLoader.dmg and build/LibertyLoader.zip"
fi
