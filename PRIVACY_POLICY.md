# Privacy Policy — Saga

*Last updated: June 2026*

Saga is a local-first Android app. This policy describes what data the app stores, what it transmits, and to whom.

---

## What Saga stores on your device

All data lives on your device and nowhere else:

- **Playback positions and bookmarks** — your current position in each book and any named bookmarks you have saved.
- **Listening history** — timestamps and durations of your listening sessions, used for the in-app stats screen.
- **Settings** — playback speed, skip intervals, theme, animation preference.
- **Downloaded audio files** — books you choose to download for offline playback.

All of the above is encrypted at rest using AES-256 (Hive) with a key stored in the Android Keystore. Downloaded files are stored in the app's private internal storage directory, inaccessible to other apps without root.

`android:allowBackup` is disabled — none of this data can be swept into Google cloud backup or extracted via `adb backup`.

---

## What Saga transmits

Saga contacts exactly two external services:

**1. plex.tv** — for sign-in and server discovery only.
- `plex.tv/api/v2/pins` — to initiate and complete the PIN-based OAuth flow.
- `plex.tv/api/v2/resources` — to discover your Plex servers.
- `plex.tv/users/sign_out.json` — when you sign out (best-effort).
- `app.plex.tv/auth` — opened in your system browser (not an in-app WebView) for the sign-in page.

Your Plex account is subject to [Plex's own Privacy Policy](https://www.plex.tv/about/privacy-legal/).

**2. Your own Plex server** — for everything else: browsing your library, streaming audio, fetching cover art, and reporting playback progress.

**Nothing else.** No analytics service, no crash reporting SDK, no advertising network, no third-party API of any kind. The Manrope font is bundled inside the app — no Google Fonts CDN call is made.

### Note on notification artwork

Android's `MediaSession` API fetches notification and lock-screen artwork using a plain URL — custom HTTP headers are not supported. To authorise this request, Saga appends your Plex token as a URL query parameter (`?X-Plex-Token=…`) to the artwork URL sent to the system. This is the only context in which your token appears in a URL rather than an HTTP header. The request goes to your own Plex server.

---

## Your Plex token

Your Plex auth token is stored exclusively in the Android Keystore via `flutter_secure_storage`. It is never written to disk in plain text, never logged, and never transmitted to any service other than your own Plex server and the plex.tv endpoints listed above.

---

## Data export

Saga includes a manual backup/restore feature that exports your bookmarks, positions, collections, and listening history to a JSON file. **The export contains no credentials** — no Plex token, no server address. You control where this file goes.

---

## Changes to this policy

If this policy changes materially, the *Last updated* date above will be updated and a note will appear in the release changelog.

---

## Contact

Questions or concerns: open an issue at [github.com/gaut3/saga](https://github.com/gaut3/saga/issues).

---

> Saga is an independent, third-party client. It is not affiliated with, endorsed by, or associated with Plex Inc. "Plex" is a trademark of Plex Inc.
