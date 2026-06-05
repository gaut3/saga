# Changelog

All notable changes to the Saga app are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [1.0.1] – 2026-06-05

### Fixed
- Import progress: clicking Restore dismissed the settings screen instead of the dialog. The confirmation dialog buttons were using the settings screen's navigator context rather than the dialog's own context — since `showDialog` pushes onto the root navigator, `Navigator.pop(settingsContext)` popped the wrong route. Same bug fixed in Clear progress dialog.
- Import progress: file picker could hang without completing the import on some Android versions (SAF + `withData: true` interaction). Now reads via file path.
- All snackbars replaced app-wide with a custom overlay toast appearing at the top of the screen, avoiding bottom navigation margin issues entirely. Toasts are tappable to dismiss early. Error toasts (playback error, server unreachable, failed import/export) stay visible for 4 seconds; informational toasts dismiss after 2.5 seconds.
- Settings screen version display was hardcoded to `v1.0.0`. Now reads from `pubspec.yaml` at runtime via `package_info_plus`.

---

## [1.0.0] – 2026-06-05

Initial public release.

### Features
- Stream or download audiobooks from your Plex server
- Encrypted local storage (AES-256, Android Keystore)
- Smart resume with configurable rewind
- Variable playback speed and skip intervals
- Chapter navigation and named bookmarks
- Custom collections with drag-to-reorder
- Listening history — daily, monthly, and all-time heatmap
- Sleep timer
- Export / import progress backup
- Three themes: Ink, Terra, Cream
- Animated mark with Reactive (RMS), Gentle, and Pause Bars modes
- Wi-Fi-only download option
