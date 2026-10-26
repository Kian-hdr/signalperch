# Signalperch

A native macOS menu bar monitor for public service status. Built by Kian Konrad Tajbakhsh.

Requires macOS 14 or later. The first enabled service in your saved order controls the menu bar icon. Reorder services using their drag grips or accessibility actions. OpenAI, Claude, GitHub, Cloudflare, Supabase and Vercel are enabled by default; Stripe is available in Settings.

- Monochrome service marks with status symbols and color badges.
- Incident details, component status, uptime history and embedded official status pages.
- Optional notifications for incidents, worsening status and recovery.
- Configurable polling and launch at login.
- Native light/dark appearance and reduced-motion support.

Public feeds describe aggregate provider status, which can lag incidents and cannot diagnose your individual account or connection. Polling pauses while the Mac sleeps. Notification banners depend on macOS permission and Focus settings.

## Build

Install full Xcode (the app icon build uses Icon Composer) and select it with xcode-select. Swift 6 or later is required.

```sh
swift test --jobs 2
./script/build_and_run.sh
```

The local development script stops an existing Signalperch process, builds a development app, and launches it. It does not install into Applications. The optional SIGNALPERCH_SIGNING_IDENTITY environment variable selects a local development signing identity; without one it falls back to ad hoc signing.

For a release build without launching or stopping another copy:

```sh
./script/build_release.sh
```

The script stages an unsigned arm64 app in dist. Signing and notarization require the maintainer's private Apple credentials. The initial downloadable release targets Apple silicon; Intel builds are unverified.

## Privacy

No account or API key is required. Preferences and notification snapshots stay in the local UserDefaults domain dev.signalperch.app. The app requests official public status feeds and loads provider websites when you select their official pages; providers receive ordinary network requests. No developer-operated analytics or backend is included.

## Validation and limitations

The test suite exercises status decoding, incident merging, freshness, notifications and reordering, with live-feed integration tests requiring internet access. As of October 27, 2026, Supabase returns HTTP 404 for maintenance history; the app reports that detail as unavailable and the associated live integration test fails. Core service summaries remain separate. One uptime HTML acceptance test requires an inspected capture and is skipped without it. Physical sleep/wake behavior, notification delivery across macOS configurations, and Intel hardware have not been comprehensively qualified. Report reproducible issues at https://github.com/Kian-hdr/signalperch/issues.

## License

Original code, documentation and original app icon are MIT licensed. Service-brand marks retain their CC0 provenance and separate trademark rights; see THIRD_PARTY_NOTICES.md and Sources/Signalperch/Resources/VECTOR_LOGO_SOURCES.md.
