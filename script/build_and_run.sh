#!/usr/bin/env bash
set -euo pipefail
MODE="${1:-run}"
APP_NAME="Signalperch"
BUNDLE_ID="dev.signalperch.app"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
pkill -x "$APP_NAME" >/dev/null 2>&1 || true
swift build
./script/build_icon.sh
BUILD_DIR="$(swift build --show-bin-path)"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ROOT_DIR/Brand/Compiled/Assets.car" "$ROOT_DIR/Brand/Compiled/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
cp -R "$BUILD_DIR/Signalperch_Signalperch.bundle" "$APP_BUNDLE/Contents/Resources/"
# SwiftPM's generated resource accessor also checks beside the executable.
cp -R "$BUILD_DIR/Signalperch_Signalperch.bundle" "$APP_BUNDLE/Contents/MacOS/"
cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
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
SIGNING_IDENTITY="${SIGNALPERCH_SIGNING_IDENTITY:-$(security find-identity -v -p codesigning | awk '/"Apple Development:/ {print $2; exit}')}"
if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="-"
  echo "No Apple development identity found; notification authorization may be unavailable." >&2
fi
codesign --force --deep --sign "$SIGNING_IDENTITY" --timestamp=none "$APP_BUNDLE"
case "$MODE" in
  run) /usr/bin/open -n "$APP_BUNDLE" ;;
  --preview|preview) /usr/bin/open -n "$APP_BUNDLE" --args --show-panel --inspect-panel ;;
  --verify|verify) /usr/bin/open -n "$APP_BUNDLE"; sleep 1; pgrep -x "$APP_NAME" >/dev/null ;;
  --debug|debug) lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME" ;;
  --logs|logs) /usr/bin/open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate 'process == "Signalperch"' ;;
  --telemetry|telemetry) /usr/bin/open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate 'subsystem == "dev.signalperch.app"' ;;
  *) echo "usage: $0 [run|--verify|--debug|--logs|--telemetry]" >&2; exit 2 ;;
esac
