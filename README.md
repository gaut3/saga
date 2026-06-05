<picture>
  <source media="(prefers-color-scheme: dark)" srcset="saga_handoff/assets/svg/lockup/saga-lockup-ink.svg">
  <img alt="Saga" src="saga_handoff/assets/svg/lockup/saga-lockup-cream.svg" width="480">
</picture>

**Saga** is a native Android audiobook player for [Plex Media Server](https://www.plex.tv/), built with Flutter. It picks up where Plex's own app leaves off — a focused listening experience designed around how audiobooks are actually consumed.

> **Vibecoded.** Saga was built entirely through conversational AI-assisted development using [Claude](https://claude.ai). Every screen, every fix, and every architectural decision was written collaboratively in chat — no traditional coding sessions. This is a personal project to make a Plex audiobook app that i can really use.

---

## Features

**Playback**
- M4B and multi-track audiobook support with embedded chapter detection and jump-to
- Book-level progress bar and seek across the full book (multi-file aware)
- Variable speed playback (0.75×–3×) with per-book speed memory and configurable default
- Background playback with lock-screen and notification controls (rewind / play-pause / fast-forward)
- Configurable skip interval (15 / 30 / 45 / 60 s) applied to notification and in-app controls
- Sleep timer — fixed duration or end-of-current-chapter
- Smart rewind on resume — proportional seek-back after a pause, capped at 60 s
- Chromecast support via native Cast SDK
- Headphone unplug auto-pause; audio focus duck / pause for calls and notifications

**Library**
- Browse your Plex audiobook library: full-text search, sort by title / author, grid or list toggle
- Browse by author with Plex thumbnail photos
- Continue Listening — most recently played books surfaced at the top of Home
- Up Next in Series — next unstarted book per custom collection, deduped against Continue Listening
- Recently Added — deduped against both upper sections
- Switch between multiple Plex libraries from Settings

**Custom Collections**
- Create, rename, and delete collections
- Drag-to-reorder within a collection (insertion order drives Up Next in Series)
- Cover auto-set from the first book; bulk add from Browse long-press select mode
- Download all tracks in a collection in one tap

**Progress & Bookmarks**
- Automatic position saving every 10 s, plus on pause, background, and process exit
- Named bookmarks with custom labels; bookmark list sheet with jump-to and delete
- Mark books as completed (tracked with timestamps, supports re-reads)
- Tappable session log per book: play/pause events with timestamps and per-session durations
- Backup and restore all progress to a JSON export (credentials-free)

**Downloads**
- Download individual tracks or full books for offline playback
- Download badge on cover tiles; seamless switch between local and stream playback

**Listening Stats — 3-tab History screen**
- **Day** — streak banner (current + longest), animated weekly bar chart, expandable day rows showing which book was played with session-level detail and jump-to-position
- **Month** — navigable monthly calendar heatmap with bookmark and completion indicators, stat cards (days listened / best day / avg per day), by-week bars, books-touched list
- **Total** — lifetime hours, finished-books shelf, 13-week contribution heatmap, streak and best-day records

**Themes**

| Ink (dark) | Cream (light) | Terracotta |
|---|---|---|
| <img src="saga_handoff/assets/svg/mark/saga-mark-ink-bg.svg" width="80"> | <img src="saga_handoff/assets/svg/mark/saga-mark-cream-bg.svg" width="80"> | <img src="saga_handoff/assets/svg/mark/saga-mark-terra-bg.svg" width="80"> |

Themes apply instantly across all screens with no restart.

---

## Requirements

- A running [Plex Media Server](https://www.plex.tv/) with an audiobook library
- An Android device (API 21+)
- A Plex account (free or Plex Pass)

---

## Building from source

**Prerequisites:** [Flutter SDK](https://flutter.dev/docs/get-started/install) (stable channel), Android SDK, a connected Android device or emulator.

```bash
git clone https://github.com/gaut3/saga.git
cd saga/saga
flutter pub get
flutter run
```

To build and install a release APK without wiping app data:

```bash
flutter build apk --release --obfuscate --split-debug-info=build/debug-info
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

> Use `adb install -r` rather than `flutter install` — the `-r` flag replaces the APK in place and preserves all Hive-encrypted local data (bookmarks, history, settings).

---

## Tech stack

| Layer | Library |
|---|---|
| UI | Flutter + Riverpod |
| Audio engine | `just_audio` + `audio_service` + `audio_session` |
| Local storage | Hive (AES-256 encrypted) |
| Secure storage | `flutter_secure_storage` (Android Keystore) |
| Networking | `dio` + `cached_network_image` |
| Cast | Google Cast SDK (Default Media Receiver) |
| M4B chapters | Custom FFmpeg metadata reader |

---

## Privacy & security

Saga is local-first with no analytics, no crash reporting SDK, and nothing transmitted anywhere except your own Plex server and `plex.tv` for sign-in.

- Plex token stored in the Android Keystore via `flutter_secure_storage`
- All local data (bookmarks, history, settings) encrypted with AES-256 via Hive
- `android:allowBackup="false"` — data cannot be swept into Google cloud backup or pulled via `adb backup`
- Progress export is credentials-free (no token, no server URL)
- No Google Fonts, no Firebase, no third-party analytics of any kind

---

## Setup

1. Open the app and sign in with your Plex account.
2. Saga will auto-discover your Plex server on the local network; remote access via relay works too.
3. Select your audiobook library from Settings if you have more than one.
4. Tap any book to start listening. Your place is saved automatically.

---

---

> Saga is an independent, third-party client. It is not affiliated with, endorsed by, or associated with Plex Inc. or Plex in any way. "Plex" is a trademark of Plex Inc.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="saga_handoff/assets/svg/wordmark/saga-wordmark-ink.svg">
  <img alt="Saga" src="saga_handoff/assets/svg/wordmark/saga-wordmark-cream.svg" width="120">
</picture>
