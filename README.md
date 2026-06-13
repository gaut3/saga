<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/png/wordmark/saga-wordmark-ink.png">
  <img alt="Saga" src="docs/assets/png/wordmark/saga-wordmark-cream.png" width="480">
</picture>

**Saga** is a native Android audiobook player for [Plex Media Server](https://www.plex.tv/), built with Flutter. It picks up where Plex's own app leaves off — a focused listening experience designed around how audiobooks are actually consumed.

> **Vibecoded** — but not blindly. Saga was built through conversational AI-assisted development with Claude: screens, fixes, and architecture worked out collaboratively in chat. Every decision was reviewed and reasoned through, not just accepted — and the result is fully open source, so you can audit exactly what it does. A personal project to make a Plex audiobook app I'd actually want to use.

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

### Network audit — every endpoint Saga contacts

| Endpoint | When | Why |
|----------|------|-----|
| `plex.tv/api/v2/pins` | Sign-in | PIN-based OAuth flow (request + poll) |
| `app.plex.tv/auth` | Sign-in | Sign-in page, opened in your **system browser** — never an in-app WebView |
| `plex.tv/api/v2/resources` | Sign-in / reconnect | Discover your Plex servers |
| `plex.tv/users/sign_out.json` | Sign-out | Invalidate the session (best-effort) |
| **Your own Plex server** | Always | Everything else: library browsing, streaming, cover art, playback progress |
| `api.github.com/repos/gaut3/saga/releases/latest` | **Opt-in only, default off** | "Check for updates on launch" (Settings → About) — one anonymous GET per launch when enabled |

**That's the complete list.** Two documented exceptions put the Plex token in a URL query instead of a header — notification artwork (Android `MediaSession` fetches art without custom headers) and Chromecast (the Cast device fetches the stream itself) — both go only to your own server. Details in the [privacy policy](PRIVACY_POLICY.md).

**Verify it yourself:** point [PCAPdroid](https://github.com/emanuele-f/PCAPdroid) (on-device, no root) at Saga — you'll see traffic only to your own server and `plex.tv` (plus `api.github.com` if you enabled update checks).

### Permissions — every entry in the manifest

| Permission | Why |
|------------|-----|
| `INTERNET` | Streaming from your Plex server |
| `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_MEDIA_PLAYBACK` | Background playback with the media notification |
| `WAKE_LOCK` | Keep playback alive with the screen off |
| `POST_NOTIFICATIONS` | The media playback notification (Android 13+) |
| `WRITE_EXTERNAL_STORAGE` (≤ Android 9) / `READ_EXTERNAL_STORAGE` (≤ Android 12) | Legacy download support on old Android versions; auto-dropped on modern Android |
| `ACCESS_NETWORK_STATE` | Wi-Fi-only downloads setting (merged in by `connectivity_plus`; read-only network-type query) |

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
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/png/wordmark/saga-wordmark-ink.png">
  <img alt="Saga" src="docs/assets/png/wordmark/saga-wordmark-cream.png" width="120">
</picture>
