#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BRAND="$ROOT/Brand"
OUT="${1:-$BRAND/Compiled}"
ICTOOL="$(dirname "$(xcode-select -p)")/Applications/Icon Composer.app/Contents/Executables/ictool"
if [[ ! -x "$ICTOOL" ]]; then
  echo "Icon Composer requires a full Xcode installation." >&2
  exit 1
fi
mkdir -p "$OUT"
"$ICTOOL" "$BRAND/Signalperch.icon" --export-image --output-file "$BRAND/Preview_Default.png" --platform macOS --rendition Default --width 1024 --height 1024 --scale 1
"$ICTOOL" "$BRAND/Signalperch.icon" --export-image --output-file "$BRAND/Preview_Dark.png" --platform macOS --rendition Dark --width 1024 --height 1024 --scale 1
xcrun actool "$BRAND/Signalperch.icon" \
  --compile "$OUT" --output-format human-readable-text --notices --warnings --errors \
  --output-partial-info-plist "$OUT/IconInfo.plist" \
  --app-icon Signalperch --include-all-app-icons --enable-on-demand-resources NO \
  --development-region en --target-device mac --minimum-deployment-target 14.0 --platform macosx
# Produce all traditional ICNS sizes for the app's macOS 14 compatibility floor.
xcrun swift "$BRAND/RenderFallback.swift" "$BRAND/Preview_Default.png" "$BRAND/Preview_Classic.png"
ICONSET="$OUT/AppIcon.iconset"
mkdir -p "$ICONSET"
for points in 16 32 128 256 512; do
  sips -z "$points" "$points" "$BRAND/Preview_Classic.png" --out "$ICONSET/icon_${points}x${points}.png" >/dev/null
  pixels=$((points * 2))
  sips -z "$pixels" "$pixels" "$BRAND/Preview_Classic.png" --out "$ICONSET/icon_${points}x${points}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$OUT/AppIcon.icns"
# Assets.car names the native icon Signalperch; the classic file is AppIcon.icns.
/usr/libexec/PlistBuddy -c 'Set :CFBundleIconFile AppIcon' "$OUT/IconInfo.plist"
echo "Icon resources: $OUT/Assets.car and $OUT/AppIcon.icns"
