# Changelog

All notable changes to the Saga app are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Unreleased]

### Added
- **Check for updates.** Settings → About → "Check for updates" opens the GitHub Releases page in the system browser. No background network activity — just a shortcut for users who want to see if a new version is available.
- **Undo seek.** After scrubbing the timeline or jumping to a chapter, bookmark, or history entry, an Undo button appears in the player action row. Tapping it jumps back to exactly where you were before the seek. One undo level — the button clears after use or after loading a new book.

### Fixed
- **Media notification stops working after extended playback (shows "Saga is running").** With `androidStopForegroundOnPause: true`, pausing stopped the foreground service and detached the notification. On Android 13+ this could leave the service in a state where Android replaced the media notification with its own generic foreground notification, requiring an app restart to recover. Changed to `androidStopForegroundOnPause: false` so the foreground service runs continuously and the media notification is always owned and controlled by audio_service.
- **RMS animation bars lag ~46 ms behind audio on top of the configured A2DP delay.** The IIR smoothing factor was 0.55, giving ~46 ms for bars to reach 90 % of the target level at 60 fps. Increased to 0.72, cutting the smoothing lag to ~29 ms — particularly noticeable for users who set a precise Bluetooth sync delay.
- **TalkBack: play/pause control (AnimatedSagaMark) had no semantic label.** The play/pause gesture area in both the full player and mini player now announces "Play" or "Pause" to screen readers.
- **TalkBack: player transport buttons had no accessibility labels.** Skip previous/next, rewind, and skip forward buttons now have tooltips read by TalkBack. Speed, Bookmark, Sleep Timer, and Undo buttons are also labelled.
- **TalkBack: progress slider announced raw fraction instead of time.** The slider now formats its value as human-readable time (e.g. "1h 23m 45s") when focused by a screen reader.
- **TalkBack: now-playing cover art in the mini player had no label.** The art thumbnail now announces "&lt;title&gt; cover art".
- **Touch targets below 44 dp.** Browse sort chips, the grid/list toggle icon, and the History Day / Month / Total segment selector all increased vertical padding to meet the minimum tap-area guideline.
- **Nav bar label text too small.** Labels were 10 dp — below the legibility floor on most devices. Increased to 12 dp.

---

## [1.0.4] – 2026-06-07

### Added
- **Sort by duration.** Browse screen now offers a "Duration" sort (shortest first), making it easy to find a book that fits a commute or flight.
- **Default sleep timer.** Settings → Playback → "Default sleep timer" lets you pick a preferred duration (Off / 15 min / 30 min / 45 min / 60 min / End of chapter). Once set, tapping the moon icon in the player starts the timer immediately — no sheet needed. If a timer is already running, tapping opens the picker so you can change the duration or cancel. The default option is always marked with a moon icon in the picker for reference.
- **Scrubber drag tooltip.** A small floating label appears above the seek thumb while dragging, showing exactly where you'll land before you release.
- **Reactive animation sync delay.** Tap the "Player animation" label in Settings → Playback to open a detail sheet. When Reactive mode is selected, a slider (0–400 ms, 10 ms steps) lets you delay the RMS animation to match Bluetooth audio latency. The delay is applied in real time as you drag and persists across launches. Try 100–200 ms for typical Bluetooth headphones.

### Fixed
- **CodeQL: array index out of bounds in `mapOf` helper (vendored just_audio).** The loop guard `i < args.length` would let the final iteration attempt `args[i + 1]` when `args` has an odd number of elements. Changed to `i + 1 < args.length` so the loop exits cleanly on a dangling key. No behaviour change for all existing (even-argument) call sites.
- **CodeQL: unnecessary boxing of `newIndex` in `updateCurrentIndex` (vendored just_audio).** `getCurrentMediaItemIndex()` returns a primitive `int`; declaring the local as `Integer` caused a redundant autobox that CodeQL flagged as never-null. Changed to `int newIndex` and rewrote the comparison as `currentIndex == null || newIndex != currentIndex` to preserve the nullable-`currentIndex` handling explicitly.
- **CodeQL: deprecated `FlutterPluginBinding.getFlutterEngine()` call removed (vendored just_audio).** `JustAudioPlugin.onAttachedToEngine` registered an `EngineLifecycleListener` via the deprecated `getFlutterEngine()` solely to call `methodCallHandler.dispose()` on hot restart. Modern Flutter embedding already routes this cleanup through `onDetachedFromEngine`, which is already implemented, so the listener and its two now-unused imports are removed.
- **CodeQL: dead local variable removed from `enqueuePlaybackEvent` (vendored just_audio).** A `HashMap` was allocated into a local `event` variable that was never read; `pendingPlaybackEvent` was being set from `createPlaybackEvent()` on the very next line. Removed the unused allocation.
- **`PlexBook` now parses `parentIndex` as `seriesIndex`.** The Plex JSON includes a volume/series index for audiobooks but it was previously discarded. The field is now stored as `int? seriesIndex` on `PlexBook`, making it available for future series-ordering features.
- **`PlexBook` now parses `titleSort` from Plex.** The Plex `titleSort` field (e.g. "Name of the Wind" for "The Name of the Wind") is now used by the A→Z and Z→A sorts in Browse, falling back to `title` when absent. This matches how Plex's own clients order books.
- **`POST_NOTIFICATIONS` permission declared for Android 13+.** The permission is now declared in the manifest and requested at runtime on first launch. An explanation dialog appears first — "Saga shows a notification with playback controls so you can pause, skip, and see what's playing from your lock screen and notification shade. Without it, the notification may not appear reliably." — so the system prompt isn't unexpected.
- **Import backup shows an error toast when the selected file cannot be read.** Previously, if the file picker returned a file with neither a path nor bytes (certain Samsung/MIUI pickers, future platforms), `pickAndParse()` returned `null` silently — indistinguishable from user-cancel. It now throws a `StateError` so the caller can show a specific "Could not read the selected file." error toast.
- **`PackageInfo.fromPlatform()` in Settings now handles platform-channel failures.** Added `.catchError((_) {})` so a failure (restricted environment, misconfigured plugin) doesn't produce an unhandled exception. The Licenses page now passes `null` instead of an empty string when the version hasn't loaded yet, so Flutter uses its own fallback rather than showing a blank version line.
- **Toast widget re-reads theme colors on every rebuild.** `_SagaToast` was a plain `StatefulWidget` whose `build()` read `SagaColors.surface`/`.fg` without watching the theme provider. If the user changed theme while a toast was visible, the toast kept its old colors. Converted to `ConsumerStatefulWidget` and added `ref.watch(sagaThemeVariantProvider)` so it rebuilds on theme change.
- **Server selection screen guards against concurrent taps.** `ServerSelectionScreen` was a stateless `ConsumerWidget`; two rapid taps on different server tiles each opened a loading dialog, and when both resolved the second `Navigator.pop` dismissed the settings screen instead of the dialog. Converted to `ConsumerStatefulWidget` with a `_selecting` bool that blocks re-entry for the duration of the selection.

---

## [1.0.3] – 2026-06-06

### Security
- **Cross-server backup restore now warns before proceeding.** Plex `ratingKey` values are per-server integers — importing a backup from a different server could silently overwrite positions for unrelated books that share the same integer key. The app now persists the connected server's `machineIdentifier` (stored in the Android Keystore alongside the token) and embeds it in every backup export (format v4). On restore, if the backup's server ID is present and differs from the current server's, a warning dialog is shown before any data is written.
- **Backup temp file is deleted after sharing.** The JSON export was written to the system temp directory and left there after `Share.shareXFiles()` returned. The file is now deleted immediately after the share sheet is dismissed.
- **CodeQL static analysis added.** `.github/workflows/codeql.yml` runs on every push/PR to `main` and weekly. It analyzes the Android/Kotlin layer (the RMS audio patch, platform channels, native plugins) using the `security-and-quality` query pack, catching taint flows, crypto misuse, and injection risks that Dart-level analysis cannot see.

### Fixed
- **Streak shows 0 before you've listened today, even if yesterday's streak is intact.** Both `_homeStreak()` (home screen strip) and `_computeStreak()` (history screen) started walking backwards from today — if today has no listening time yet the loop exits immediately, reporting 0. They now start from yesterday when today is empty, so the streak stays visible all day until you either extend it or midnight passes. Also applied the DST midnight-renormalization fix to `_homeStreak()` (missed in 1.0.2).
- **Download mark no longer stays frozen at the bottom.** The progress passed to `AnimatedSagaMark` was a whole-track count (`downloadedCount / total`), which stays at 0.0 for the entire download of a single-file audiobook. It now incorporates the actual byte-level progress reported by Dio, so the bars fill smoothly from floor to full. The button label also now shows a percentage (`Downloading 34%…`) instead of `Downloading 0 / 1…`.
- **Playback speed resets to default when resuming from the Continue Listening card.** The home screen's Resume card called `loadBook()` and `play()` without restoring the per-book saved speed, so a book set to 2× would silently drop back to the global default on the next resume. Both the resume-and-play path and the load-only (open player) path now restore speed identically to the book detail Resume button. Same fix applied to the stream-error auto-reload path in `player_provider.dart`.
- **Today's bar in the home weekly sparkline could show the wrong colour on DST transition days.** The seven `weekDays` entries were built with `Duration(days: N)` additions without renormalizing to midnight. Across a spring-forward boundary the time component drifts to 01:00, causing the `isToday` equality check to fail and today's bar to appear as a past-day colour. Each entry is now renormalized to midnight after the addition (same pattern as the existing `monday` renormalization above it).
- **"Avg / day" in the Month history tab showed an inflated average.** The stat divided total listening time by the number of days the user actually listened, not by the number of days in the month. A user who listened on 3 of 30 days would see roughly 10× the true daily average. The denominator is now `daysInMonth`, matching what the label says.
- **Global download indicator added.** A 3 px accent-colored progress bar appears at the top of the bottom bar (above the mini player) on every screen while a download is active, so there is always a visible signal that something is downloading even after leaving the book detail screen.

---

## [1.0.2] – 2026-06-06

### Fixed
- **"Clear listening progress" now actually clears everything.** Previously only bookmark positions were deleted; listening history, streaks, heatmap, completed-book records, named bookmarks, and session logs all survived. The confirmation dialog now lists every category being erased, and the action wipes all six stores and updates the UI immediately.
- **Error toasts are now visually distinct from informational toasts.** Added an `isError` parameter to `showSagaToast`; error toasts use the amber accent background with ink text — fixed colors that contrast against all three themes. Playback errors, server-unreachable warnings, and import/export failures all use the error style.
- **Toast re-entry crash fixed.** Tapping to dismiss a toast while its auto-dismiss timer was already firing could call `entry.remove()` twice, crashing the overlay. A `_dismissed` guard prevents double-invocation.
- **Toast positioning no longer goes stale after device rotation.** The status-bar padding was previously captured at call time; it is now read inside the `OverlayEntry` builder so it reflects the actual inset at render time.
- **Toast now appears above the full-screen player.** Toasts are inserted into the root navigator's overlay instead of the tab overlay, so playback error toasts are visible even when the player screen is open.
- **Browse search no longer carries over when switching Plex libraries.** Switching the active library in Settings now clears the search query, select mode, and selection state in the Browse screen.
- **Position loss: stream error during loading no longer overwrites resume point with 0ms.** The playback-event error handler now guards behind `processingState == ready` before saving, matching the existing periodic-save guard. A server 401 or network drop during `setAudioSource` (loading state) no longer writes `Duration.zero` to `BookmarkStore`.
- **Position loss: backgrounding while buffering on a slow connection no longer loses position.** A new `savePositionForLifecycle()` method bypasses the `processingState == ready` guard (only skipping truly idle/completed states). App lifecycle events (`paused`, `hidden`, `detached`) now call this instead of `savePosition()`, so Android killing the app mid-buffer no longer leaves the position up to 10 s stale.
- **Position loss: `BookmarkStore` no longer wipes all saved positions on a transient I/O error.** The `HiveError` catch in `init()` now checks the error message and only wipes + recreates the box for decryption failures ("wrong key" / "corrupt"). Any other `HiveError` (truncated file from an unclean OS kill, etc.) is rethrown rather than silently deleting every position.
- **Position loss: restoring a backup no longer silently rewinds books with newer local positions.** Restore now detects conflicts (backup position older than local). When conflicts exist, a per-book dialog shows "Keep current" and "Restore from backup" options for each affected book, with a bulk "Keep all current / Restore all" toggle when more than three books are affected. "Keep current" is the safe default. Non-conflicting entries restore without prompting.
- **Library parse crash on books with missing titles.** `PlexBook.fromJson` was casting `json['title']` directly to `String`; Plex sometimes returns a null title for partially-indexed files. A single such item crashed the entire library fetch, leaving the home screen in a permanent error state. Now falls back to an empty string.
- **Sleep timer "end of chapter" fired immediately when already in the last chapter.** The chapter search used `orElse: () => chapters.last`, which returned the already-past start of the final chapter; the computed remaining time was ≤ 0 and `pause()` fired at once. Now targets the file duration when no upcoming chapter exists.
- **Mini player showed placeholder icon instead of cover art for downloaded books.** `_ArtThumbnail` was using `Image.network()` unconditionally; `file://` URIs from offline books always triggered the error builder. Now branches on `uri.scheme == 'file'` and uses `Image.file()`, matching the full player screen's cover art widget.
- **Streak and week strip showed wrong values after clocks change (DST).** Two remaining instances of `Duration(days: N)` subtraction without midnight renormalization: `_computeStreak()` (both current and longest streak loops) and `_ListeningStrip`'s Monday calculation. On a spring-forward Sunday, subtraction would land at 23:00, causing store lookups to miss and show zero. Both now renormalize to midnight via `DateTime(y, m, d)` after every subtraction, consistent with the earlier heatmap and streak fixes.

---

## [1.0.1] – 2026-06-05

### Fixed
- Import progress: clicking Restore dismissed the settings screen instead of the dialog. The confirmation dialog buttons were using the settings screen's navigator context rather than the dialog's own context — since `showDialog` pushes onto the root navigator, `Navigator.pop(settingsContext)` popped the wrong route. Same bug fixed in Clear progress dialog.
- Import progress: file picker could hang without completing the import on some Android versions (SAF + `withData: true` interaction). Now reads via file path.
- All snackbars replaced app-wide with a custom overlay toast appearing at the top of the screen, avoiding bottom navigation margin issues entirely. Toasts are tappable to dismiss early. Error toasts (playback error, server unreachable, failed import/export) stay visible for 4 seconds; informational toasts dismiss after 2.5 seconds.
- Settings screen version display was hardcoded to `v1.0.0`. Now reads from `pubspec.yaml` at runtime via `package_info_plus`.

### Changed
- User-facing text pass: "Relisten" → "Listen again"; "From Start" → "From start"; "times read" → "times listened"; "reading/book positions" → "listening positions"; server connection count now uses correct singular/plural; search hint no longer mentions genre (genre is not searchable); "Up next · " separator changed to "Up next in "; "Skip back a little when resuming after a pause" reworded to "Rewind slightly when resuming playback".

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
