<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/png/wordmark/saga-wordmark-ink.png">
  <img alt="Saga" src="docs/assets/png/wordmark/saga-wordmark-cream.png" width="480">
</picture>

**Saga** is a native Android audiobook player for [Plex Media Server](https://www.plex.tv/), built with Flutter. Plex's own app plays an audiobook like an album. Saga plays it like a book: chapters, bookmarks, a sleep timer, and it remembers where you were.

**[saga-app.no](https://saga-app.no)** — screenshots, themes, and the mark in motion.

> **Vibecoded** — but not blindly. Saga was built through conversational AI-assisted development with Claude: screens, fixes, and architecture worked out collaboratively in chat. Every decision was reviewed and reasoned through, not just accepted — and the result is fully open source, so you can audit exactly what it does. A personal project to make a Plex audiobook app I'd actually want to use.

---

## Features

**Playback**
- M4B and multi-track audiobook support with embedded chapter detection and jump-to — both MP4 chapter conventions (Nero `chpl` and QuickTime chapter tracks)
- Book-level progress bar and seek across the full book (multi-file aware), or scrub within the current chapter instead
- Time remaining at your actual playback speed; tap to switch to the total length (the book's, or the chapter's when scrubbing by chapter). Scrubbing by chapter still shows how much of the book is left
- Variable speed playback (0.75×–3×) with per-book speed memory and configurable default
- Skip silence — quiet stretches in the narration go by faster, audio untouched (off by default)
- Volume boost (+3/+6/+9 dB) for quiet narrators, applied on the phone after decoding — works on any book without touching your server's files (off by default)
- Background playback with lock-screen and notification controls: skip back, play-pause and skip forward, the skip buttons showing your skip lengths
- Skip back and skip forward set separately (15 / 30 / 45 / 60 s each), used by the player, the notification, the lock screen, the widget and Android Auto
- Undo after a scrub or a jump to a chapter, bookmark or session
- Sleep timer — fixed duration or end-of-current-chapter, easing the volume down over the last fifteen seconds instead of cutting off mid-word
- Smart rewind on resume — proportional seek-back after a pause, capped at 60 s
- Auto-play the next book in a collection, with a cancellable countdown (off by default)
- Tap the cover on the player to look through it at the book's details
- Always-visible mini player; swipe it away to dismiss, long-press for options
- Home-screen widget — the book you're listening to, with cover, chapter, progress, resume or pause and your skip buttons. Resize it to change its shape: one row, a wide card that also shows the time left, or the cover on its own above the controls. It works with Saga closed and wears the theme you picked
- Chromecast support via native Cast SDK: the player's Device button lists this phone and the Google Cast devices on your network. The whole book is cast as one queue, the notification, lock screen, headset and widget drive the TV, the sleep timer and listening stats work on it, and your place is handed back when casting ends. A cast left paused or finished for 10 minutes lets the TV go. Google Cast devices only (Chromecasts, Google TV, Nest speakers): TVs with their own casting systems, like most Roku and LG models, don't appear
- Bluetooth speakers, receivers and car stereos work like headphones: the book plays on the phone and is sent to them, so everything above applies, including the sleep timer, smart rewind and listening stats. The phone has to stay in range
- Headphone unplug auto-pause; auto-resume after calls and brief interruptions (on by default, and never over another app's media)
- Android Auto — Continue listening, Downloaded, and your collections in the order you dragged them, as a grid of covers showing your progress and what's downloaded; the player's queue is the book's chapters. Built from what's already on the phone, so a downloaded book plays in the car with no server involved. Asking for a book by name works too. The same browse tree backs the lock screen's media-resumption card. Android Auto hides apps that don't come from the Play Store until you allow them: see [Troubleshooting](#troubleshooting)

**Library**
- Browse your Plex audiobook library: search across titles and authors — narrators too, once the one-tap narrator index is built; sort by title, author, length or narrator (each reversible); grid or list toggle
- Filter to Want to read or Downloaded books ("Saved" in 1.1.3)
- Want to Read — star a book on its page to keep it on its own shelf on Home
- Browse by author with Plex thumbnail photos
- Narrator and genre on the book screen — Plex has no narrator field, so Saga reads the **Style** tags audiobook libraries use for it, fetched once per book and kept for offline
- Continue Listening — the book you're in the middle of at the top of Home, with the others under "Also in progress", and your week and streak at a glance above it
- Up Next in Series — next unstarted book per custom collection, deduped against Continue Listening
- Recently Added — deduped against both upper sections
- Switch between multiple Plex libraries from Settings

**Custom Collections**
- Create, rename, and delete collections
- Drag-to-reorder within a collection (insertion order drives Up Next in Series)

**Progress & Bookmarks**
- Automatic position saving every 10 s, plus on pause, background, and process exit
- Named bookmarks with a label and an optional note; bookmark list sheet with jump-to and delete
- Mark books as completed (tracked with timestamps, supports re-reads)
- Listening sessions per book: where each one started and ended, the chapter it ended in, and how long you listened. Tap one to hear about thirty seconds around where it ended without moving your place, then Resume from there: for the night you fall asleep listening. In the player, on each book's page and in History
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

## Installing and updating

Saga isn't on the Play Store. Each [release](https://github.com/gaut3/saga/releases/latest) has two APKs:

- **`saga-arm64-v8a.apk`** (about 21 MB) for almost any phone from the last several years. Pick this one if you're not sure.
- **`saga.apk`** (about 58 MB), the universal build, for older 32-bit phones and anything the first one won't install on.

**Keep to the one you picked.** Android refuses an update that looks older than what's installed, and the arm64 build is numbered higher than the universal one, so the universal APK can't install over the arm64 one. Moving from universal to arm64 works.

**To check a download,** compare it with the `.sha256` file beside it (`sha256sum -c saga-arm64-v8a.apk.sha256`), or confirm GitHub built it from this repository: `gh attestation verify saga-arm64-v8a.apk --repo gaut3/saga`.

**To update,** install the new APK over the old one; your places, downloads and settings stay. Saga can tell you when there's a new release: Settings → About → "Check for updates automatically" (off by default). Or let [Obtainium](https://github.com/ImranR98/Obtainium) do it: add `https://github.com/gaut3/saga`, and set its APK filter to `arm64-v8a` if that's the build you use. Turn on "Include prereleases" only if you want betas.

**Never uninstall Saga to get past an install error.** Uninstalling erases your places, bookmarks and history along with the app. If a reinstall is truly needed, export first: Settings → Data & backup → Export progress, and use Import progress in the same place afterwards.

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
| `api.github.com/repos/gaut3/saga/releases/latest` (beta versions: `…/releases`) | **Opt-in only, default off** | "Check for updates automatically" (Settings → About) — one anonymous GET when Saga starts, and once a day if it stays open, when enabled |

**That's the complete list.** Everything authenticates with the token in an HTTP header, with **one** exception: Chromecast, because a Cast device fetches the stream itself and cannot send headers, so the credential has to travel in the URL. Since 1.1.0 that URL carries a **delegated token** requested from your server rather than your account token, because a Cast device reports what it is playing to anything else on the network that asks. Plex means a delegated token to work only on that one server and to expire by itself, but a published flaw in Plex Media Server ([CVE-2025-69414](https://www.cve.org/CVERecord?id=CVE-2025-69414), with no fix announced that we know of) lets one be traded for a permanent token for your account. So on an affected server it protects less than it was meant to; it is still better than putting the account token itself in the URL. If your server is too old to mint one, Saga falls back to the account token rather than refusing to cast, and drops the cover art so the key travels only in the audio URLs (one per file of the book, since 1.2.0 casts the whole book as a queue). Notification and lock-screen artwork was the second exception until 1.1.0; it no longer involves the token at all. Details in the [privacy policy](PRIVACY_POLICY.md).

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

1. Open the app and sign in with your Plex account: in the browser, or with a code at plex.tv/link if the browser doesn't hand you back to Saga.
2. Pick your server. Saga gets the list from your Plex account and tries each of the server's addresses, preferring one on your home network, then a remote one, then Plex's relay. It checks again when your network changes, so it follows you out of the house and back.
3. Select your audiobook library from Settings if you have more than one.
4. Tap any book to start listening. Your place is saved automatically.

## Troubleshooting

**Playback stops on its own after the screen has been off for a while** (common on Samsung, Xiaomi, OnePlus, and other heavily customized Android builds): the manufacturer's battery manager is killing Saga despite its playback service. Exclude Saga from battery optimization — **Android Settings → Apps → Saga → Battery → Unrestricted** (wording varies by brand). [dontkillmyapp.com](https://dontkillmyapp.com) has step-by-step instructions per manufacturer. Saga already does everything an app can do from its side (foreground playback service, wake and Wi-Fi locks); this last step is unfortunately in the system's hands.

If playback was stopped this way, your position is safe — Saga saves it continuously — and the notification's play button or the app will resume where you left off.

**Saga doesn't appear on the car's screen in Android Auto**, though audio may still play through the car: Android Auto only lists apps installed from the Play Store until you allow others. Open Android Auto's settings (on Pixels and most phones: **Android Settings → Connected devices → Connection preferences → Android Auto**; elsewhere search Settings for "Android Auto", or open **Settings → Apps → Android Auto** and its in-app settings), scroll to **Version** and tap it about ten times to turn on developer mode, then **⋮ → Developer settings → Unknown sources**. Reconnect to the car and Saga is in the app list.

---

> Saga is an independent, third-party client. It is not affiliated with, endorsed by, or associated with Plex Inc. or Plex in any way. "Plex" is a trademark of Plex Inc.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/png/wordmark/saga-wordmark-ink.png">
  <img alt="Saga" src="docs/assets/png/wordmark/saga-wordmark-cream.png" width="120">
</picture>
