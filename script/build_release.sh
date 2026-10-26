#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
swift build -c release --jobs 2
./script/build_icon.sh
BIN="$(swift build -c release --show-bin-path)"
APP="$ROOT/dist/Signalperch.app"
if [[ -e "$APP" ]]; then echo "Output already exists: $APP" >&2; exit 1; fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Signalperch" "$APP/Contents/MacOS/"
cp -R "$BIN/Signalperch_Signalperch.bundle" "$APP/Contents/Resources/"
cp -R "$BIN/Signalperch_Signalperch.bundle" "$APP/Contents/MacOS/"
cp Brand/Compiled/Assets.car Brand/Compiled/AppIcon.icns "$APP/Contents/Resources/"
cp LICENSE THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Signalperch</string>
<key>CFBundleIdentifier</key><string>dev.signalperch.app</string>
<key>CFBundleName</key><string>Signalperch</string>
<key>CFBundleDisplayName</key><string>Signalperch</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconName</key><string>Signalperch</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleShortVersionString</key><string>0.3.1</string>
<key>CFBundleVersion</key><string>4</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
printf 'Unsigned release app: %s\n' "$APP"
