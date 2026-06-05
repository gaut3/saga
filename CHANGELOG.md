# Changelog

All notable changes to the Saga app are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [1.0.1] – 2026-06-05

### Fixed
- Import progress: file picker could hang and leave the dialog open without completing the import (Android SAF + `withData: true` interaction). Now reads via file path, which is reliable across Android versions.

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
