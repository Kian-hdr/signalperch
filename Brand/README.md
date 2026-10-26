# Signalperch app icon

Original vector radio signal perched on a mast, with a cool teal/blue background and a restrained pale glass foreground. No external artwork or generated raster source is used.

Editable source: `Signalperch.icon` and `Signalperch.icon/Assets/Signal.svg`.

Rebuild from the repository root:

```bash
script/build_icon.sh
```

Requires full Xcode with Icon Composer, `actool`, `swift`, `sips`, and `iconutil`. No third-party build dependency is required.

Copy `Compiled/Assets.car` and `Compiled/AppIcon.icns` to the app's `Contents/Resources`. Set these app `Info.plist` keys before signing:

```xml
<key>CFBundleIconName</key><string>Signalperch</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
```

`Assets.car` contains the native layered icon. `AppIcon.icns` contains the classic macOS fallback at all standard 16–1024 pixel sizes with classic macOS optical padding. `Compiled/IconInfo.plist` contains the same icon metadata.

Validation on 02-Oct-2026: bundled compose-app-icon schema validation passed; Icon Composer 27.0 rendered Default and Dark successfully; Xcode 27.0 actool compiled for minimum macOS 14.0; assetutil decoded Assets.car; iconutil generated the classic ICNS. App integration, signing and runtime verification are owned by the application build workflow.

Apple guidance: https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer
