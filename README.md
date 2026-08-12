<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/png/wordmark/saga-wordmark-ink.png">
  <img alt="Saga" src="docs/assets/png/wordmark/saga-wordmark-cream.png" width="480">
</picture>

**Saga** is a native Android audiobook player for [Plex Media Server](https://www.plex.tv/), built with Flutter. It picks up where Plex's own app leaves off — a focused listening experience designed around how audiobooks are actually consumed.

**[saga-app.no](https://saga-app.no)** — screenshots, themes, and the mark in motion.

> **Vibecoded** — but not blindly. Saga was built through conversational AI-assisted development with Claude: screens, fixes, and architecture worked out collaboratively in chat. Every decision was reviewed and reasoned through, not just accepted — and the result is fully open source, so you can audit exactly what it does. A personal project to make a Plex audiobook app I'd actually want to use.

---

## Features

**Playback**
- M4B and multi-track audiobook support with embedded chapter detection and jump-to — both MP4 chapter conventions (Nero `chpl` and QuickTime chapter tracks)
- Book-level progress bar and seek across the full book (multi-file aware), or scrub within the current chapter instead
- Time remaining at your actual playback speed; tap to switch to the book's total length
- Variable speed playback (0.75×–3×) with per-book speed memory and configurable default
- Skip silence — quiet stretches in the narration go by faster, audio untouched (off by default)
- Volume boost (+3/+6/+9 dB) for quiet narrators, applied on the phone after decoding — works on any book without touching your server's files (off by default)
- Background playback with lock-screen and notification controls (rewind / play-pause / fast-forward)
- Configurable skip interval (15 / 30 / 45 / 60 s) applied to notification and in-app controls
- Sleep timer — fixed duration or end-of-current-chapter, easing the volume down over the last fifteen seconds instead of cutting off mid-word
- Smart rewind on resume — proportional seek-back after a pause, capped at 60 s
- Auto-play the next book in a collection, with a cancellable countdown (off by default)
- Tap the cover on the player to look through it at the book's details
- Always-visible mini player; swipe it away to dismiss, long-press to stop playback
- Chromecast support via native Cast SDK
- Headphone unplug auto-pause; auto-resume after calls and brief interruptions (on by default, and never over another app's media)
- Android Auto — Continue listening, Downloaded, and your collections in the order you dragged them; built from what's already on the phone, so a downloaded book plays in the car with no server involved. Asking for a book by name works too. The same browse tree backs the lock screen's media-resumption card

**Library**
- Browse your Plex audiobook library: search across titles, authors and narrators; sort by title, author, length or narrator (each reversible); grid or list toggle
- Filter to Saved or Downloaded books
- Browse by author with Plex thumbnail photos
- Narrator and genre on the book screen — Plex has no narrator field, so Saga reads the **Style** tags audiobook libraries use for it, fetched once per book and kept for offline
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
- Downloaded books open and play with the server unreachable — track metadata is stored alongside the audio

**Listening Stats — 3-tab History screen**
- **Day** — streak banner (current + longest), animated weekly bar chart, expandable day rows showing which book was played with session-level detail and jump-to-position
- **Month** — navigable monthly calendar heatmap with bookmark and completion indicators, stat cards (days listened / best day / avg per day), by-week bars, books-touched list
- **Total** — lifetime hours, finished-books shelf, 13-week contribution heatmap, streak and best-day records

**The mark**

The four-spine mark is the play/pause control and the playback indicator in one — it morphs between a play triangle and four spines, and carries buffering, downloading and finished states in the same shape. Three motion modes while playing: **Reactive**, where the spines track the audio's real loudness (read from the decoded stream, so no microphone permission), **Gentle**, a synthetic envelope, or static **Pause bars**.

A still image undersells it — [tap through every state at saga-app.no](https://saga-app.no/#mark-demo).

**Themes**

| Ink (dark) | Cream (light) | Ember (deep terracotta) | Onyx (OLED) |
|---|---|---|---|
| <img src="brand/assets/svg/mark/saga-mark-ink-bg.svg" width="80"> | <img src="brand/assets/svg/mark/saga-mark-cream-bg.svg" width="80"> | <img src="brand/assets/svg/mark/saga-mark-ember-bg.svg" width="80"> | <img src="brand/assets/svg/mark/saga-mark-onyx-bg.svg" width="80"> |

Onyx is true black — the page is `#000000`, so those pixels are physically off on an OLED screen — with warm near-black surfaces and slightly softened text so nothing blooms during night listening.


---

## Requirements

- A running [Plex Media Server](https://www.plex.tv/) with an audiobook library
- An Android device running 7.0 or later (API 24+)
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
| M4B chapters | Hand-written MP4 atom parser — no FFmpeg, no native decoder |

---

## Privacy & security

Saga is local-first with no analytics, no crash reporting SDK, and nothing transmitted anywhere except your own Plex server and `plex.tv` for sign-in — plus GitHub, only if you switch on the optional update check, which is off by default.

- Plex token stored in the Android Keystore via `flutter_secure_storage`
- All local data (bookmarks, history, settings) encrypted with AES-256 via Hive
- `android:allowBackup="false"` — data cannot be swept into Google cloud backup or pulled via `adb backup`
- Progress export is credentials-free (no token, no server URL)
- Diagnostics are written to a small local log for bug reports — never transmitted, and never sent anywhere by Saga at all. "Copy diagnostics" puts it on your clipboard; it goes somewhere only if you paste it there. Your token, your server's address and its machine identifier are masked before anything is written, and again when it's copied
- No Google Fonts, no Firebase, no third-party analytics of any kind
- **What isn't private, stated plainly:** to work on the lock screen and in a car, Saga has to tell Android what you're listening to, and Android lets any installed app read that — the books you're part-way through, your downloads and collections, and what's playing now. No password or server address is ever exposed this way, and that's asserted by a test rather than a promise, but the titles are visible. Every media app offering these features is in the same position. The progress export is likewise unencrypted: credentials-free, but it contains your bookmark notes and listening history, so treat the file accordingly

### Network audit — every endpoint Saga contacts

| Endpoint | When | Why |
|----------|------|-----|
| `plex.tv/api/v2/pins` | Sign-in | PIN-based OAuth flow (request + poll) |
| `app.plex.tv/auth` | Sign-in | Sign-in page, opened in your **system browser** — never an in-app WebView |
| `plex.tv/api/v2/resources` | Sign-in / reconnect | Discover your Plex servers |
| `plex.tv/users/sign_out.json` | Sign-out | Invalidate the session (best-effort) |
| **Your own Plex server** | Always | Everything else: library browsing, streaming, cover art, playback progress |
| `api.github.com/repos/gaut3/saga/releases/latest` | **Opt-in only, default off** | "Check for updates on launch" (Settings → About) — one anonymous GET per launch when enabled |

**That's the complete list.** Everything authenticates with the token in an HTTP header, with **one** exception: Chromecast, because a Cast device fetches the stream itself and cannot send headers, so the credential has to travel in the URL. Since 1.1.0 that URL carries a **delegated token** requested from your server — scoped to that one server and self-expiring — rather than your account token, because a Cast device reports what it is playing to anything else on the network that asks. Notification and lock-screen artwork was the second exception until 1.1.0; it no longer involves the token at all. Details in the [privacy policy](PRIVACY_POLICY.md).

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

The built manifest also carries `com.gaut3.saga.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`, which AndroidX defines and grants to Saga alone so its own runtime broadcast receivers aren't reachable by other apps. It grants no access to anything on the device.

---

## Setup

1. Open the app and sign in with your Plex account.
2. Saga will auto-discover your Plex server on the local network; remote access via relay works too.
3. Select your audiobook library from Settings if you have more than one.
4. Tap any book to start listening. Your place is saved automatically.

## Troubleshooting

**Playback stops on its own after the screen has been off for a while** (common on Samsung, Xiaomi, OnePlus, and other heavily customized Android builds): the manufacturer's battery manager is killing Saga despite its playback service. Exclude Saga from battery optimization — **Android Settings → Apps → Saga → Battery → Unrestricted** (wording varies by brand). [dontkillmyapp.com](https://dontkillmyapp.com) has step-by-step instructions per manufacturer. Saga already does everything an app can do from its side (foreground playback service, wake and Wi-Fi locks); this last step is unfortunately in the system's hands.

If playback was stopped this way, your position is safe — Saga saves it continuously — and the notification's play button or the app will resume where you left off.

---

> Saga is an independent, third-party client. It is not affiliated with, endorsed by, or associated with Plex Inc. or Plex in any way. "Plex" is a trademark of Plex Inc.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/png/wordmark/saga-wordmark-ink.png">
  <img alt="Saga" src="docs/assets/png/wordmark/saga-wordmark-cream.png" width="120">
</picture>
