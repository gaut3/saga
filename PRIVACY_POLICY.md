# Privacy Policy — Saga

*Last updated: August 2026*

Saga is a local-first Android app. This policy describes what data the app stores, what it transmits, and to whom.

---

## What Saga stores on your device

All data lives on your device and nowhere else:

- **Playback positions and bookmarks** — your current position in each book and any named bookmarks you have saved.
- **Listening history** — timestamps and durations of your listening sessions, used for the in-app stats screen.
- **Settings** — playback speed, skip intervals, theme, animation preference.
- **Downloaded audio files** — books you choose to download for offline playback.

Positions, bookmarks, history and settings are encrypted at rest using AES-256 (Hive) with a key stored in the Android Keystore. Downloaded audio files are **not** encrypted — they are ordinary audio files, and an audio player must be able to read them directly. Their protection is the app's private internal storage directory, inaccessible to other apps without root.

`android:allowBackup` is disabled — none of this data can be swept into Google cloud backup or extracted via `adb backup`.

---

## What Saga transmits

Saga contacts exactly two external services (plus one strictly opt-in check, below):

**1. plex.tv** — for sign-in and server discovery only.
- `plex.tv/api/v2/pins` — to initiate and complete the PIN-based OAuth flow.
- `plex.tv/api/v2/resources` — to discover your Plex servers.
- `plex.tv/users/sign_out.json` — when you sign out (best-effort).
- `app.plex.tv/auth` — opened in your system browser (not an in-app WebView) for the sign-in page.

Your Plex account is subject to [Plex's own Privacy Policy](https://www.plex.tv/about/privacy-legal/).

**2. Your own Plex server** — for everything else: browsing your library, streaming audio, fetching cover art, and reporting playback progress.

**3. api.github.com — only if you turn it on.** Settings → About has a "Check for updates on launch" toggle, **off by default**. When enabled, the app makes a single anonymous GET request to `api.github.com/repos/gaut3/saga/releases/latest` once per launch to compare the latest release tag with your installed version. The request carries no account data, no token, and nothing about your library; GitHub sees your IP address, as with any web request. Turning the toggle off stops the request entirely.

**Nothing else.** No analytics service, no crash reporting SDK, no advertising network, no third-party API of any kind. The Manrope font is bundled inside the app — no Google Fonts CDN call is made.

### Note on notification artwork

*Changed in 1.1.0.* Notification and lock-screen artwork no longer involves your token at all. Saga downloads the cover itself, with the token in an HTTP header, and hands the system a path to the copy on your phone. A cover Saga doesn't have yet is simply absent until the book is opened once. Earlier versions appended the token to the artwork URL given to the system, because Android's `MediaSession` cannot send headers — that is no longer done anywhere.

### Note on Chromecast

When you cast a book, the Chromecast device fetches the audio stream directly from your Plex server — the audio does not pass through the phone. A Cast device cannot send HTTP headers, so the credential has to travel in the stream URL. **This is the only remaining place where a credential appears in a URL rather than a header.**

It matters more than it looks: a Chromecast will tell anything else on the same network what it is currently playing, URL included, without asking for proof of anything. So *which* credential is in that URL is the whole question. *Changed in 1.1.0:* Saga now asks your server for a delegated token — one that works only on that server and expires by itself — and casts with that. If your server cannot issue one, Saga falls back to your account token rather than refusing to cast, and in that case sends no cover art, so the credential travels in one place instead of two.

### Note on your device identifier

On first run Saga generates a random identifier for this installation and sends it to plex.tv as `X-Plex-Client-Identifier`. Plex requires this to associate a sign-in with a device; it is how "Saga on your phone" appears in your Plex account's device list. It is random, contains nothing about you or your phone, and is not shared with anyone but Plex. It persists across sign-out, so signing back in re-uses the same device entry rather than creating a new one each time. Clearing the app's data resets it.

---

## Your Plex token

Your Plex auth token is stored exclusively in the Android Keystore via `flutter_secure_storage`. It is never written to disk in plain text, never logged, and never transmitted to any service other than your own Plex server and the plex.tv endpoints listed above.

---

## What other apps and other people can see

Saga stores your data privately, but some of it is deliberately published to Android so that features you asked for can work. This is what that means in practice.

**Other apps on your phone.** To appear in a car and on the lock screen, Saga has to publish a media browse service, and Android gives any installed app access to it without requiring a permission. Through it, another app can read the books you are part-way through, the books you have downloaded, your collection names, and each book's title, author, cover and length — and can start or pause playback. Anything you are currently playing is also readable, including the position, by any app you have granted notification access to. **No credential is exposed this way** — Saga puts no token, and no address that would let anything reach your server, into either surface. But the fact of what you are listening to is visible, and that is the price of Android Auto, lock-screen controls and "play X in Saga". There is no way to offer those features and hide this.

**Anyone who can see your screen.** Saga does not block screenshots or hide itself from the app switcher, so a book cover or title can appear in a screen recording or in the recents view. On a locked phone, the playback notification shows the current book's title, author and cover to anyone holding it — Android's own "hide sensitive notification content" setting is the control for that, and Saga cannot override it. If you want your server's address hidden from screenshots of the Settings screen, there is a **Redact server address** toggle in Settings → Server.

---

## What signing out removes

Signing out clears your Plex token, your server address and its identifier, and every cached cover.

It deliberately keeps your listening data: positions, bookmarks, history, collections, and downloaded audio files. Signing back in must never cost you your place, and downloads you are part-way through are yours. If you want that data gone, **Settings → Clear listening progress** removes positions, bookmarks and history, and the storage manager in Settings deletes downloads per book. Uninstalling the app removes everything.

Note that this data is not tied to the Plex account it came from — if you sign in with a different account on the same install, the previous account's history and downloads are still there.

---

## Data export

Saga includes a manual backup/restore feature that exports your bookmarks, positions, collections, and listening history to a JSON file. **The export contains no credentials** — no Plex token, no server address, no password.

Two things about it are worth knowing before you send it anywhere. It does contain your Plex server's *machine identifier*, which is how a restore knows the backup belongs to that server; it is not a credential and grants no access, but it does identify the server. And the file is plain, unencrypted JSON: positions, the text of any notes you wrote on bookmarks, which books you finished and when, and your listening history down to individual sessions. That is a detailed picture of your reading, so treat the file the way you would treat a diary — you control where it goes, and once it is in another app it is out of Saga's hands.

---

## Changes to this policy

If this policy changes materially, the *Last updated* date above will be updated and a note will appear in the release changelog.

---

## Contact

Questions or concerns: open an issue at [github.com/gaut3/saga](https://github.com/gaut3/saga/issues).

---

> Saga is an independent, third-party client. It is not affiliated with, endorsed by, or associated with Plex Inc. "Plex" is a trademark of Plex Inc.
