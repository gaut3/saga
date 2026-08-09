import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import 'server_scope.dart';
import 'user_box.dart';

const _boxName = 'settings';

class SettingsStore {
  static late Box _box;

  // A user-data box: it holds `primaryServerId`, which every scoped store's
  // keys are resolved against — wiping it on a transient open failure would
  // re-map a second-server user's entire library.
  static Future<void> init(List<int> encKey) async {
    _box = await openUserBox(_boxName, encKey);
  }

  /// The first Plex server this install ever selected, by machine identifier.
  ///
  /// [ServerScope] files that server's books under bare rating keys and every
  /// other server's under prefixed ones, which is what lets scoping arrive
  /// without rewriting a single existing record. Written once and then left
  /// alone — changing it would strand the data it identifies.
  static String? get primaryServerId =>
      _box.get('primaryServerId') as String?;

  static Future<void> setPrimaryServerId(String id) =>
      _box.put('primaryServerId', id);

  /// The most recently active server, by machine identifier.
  ///
  /// Where [primaryServerId] is written once and never changes (the keys filed
  /// under it depend on that), this one follows every switch. It is what a
  /// signed-out session scopes to, so the downloads still on the device keep
  /// resolving to the records they were made under — falling back to the
  /// *primary* instead made a secondary-server user's library invisible the
  /// moment they signed out.
  static String? get lastServerId => _box.get('lastServerId') as String?;

  static Future<void> setLastServerId(String id) =>
      _box.put('lastServerId', id);

  /// Whether the one-time purge of token-bearing image cache entries has run.
  ///
  /// Covers used to be fetched with the Plex token in the query string, and
  /// `CachedNetworkImage` keys its on-disk database by URL — so every cover a
  /// listener had ever viewed left a copy of a still-valid, account-wide token
  /// in plaintext, which signing out did not touch. Redacting new writes is not
  /// enough when the old ones are still sitting there; they have to be cleared
  /// on the way past, the same as the diagnostics log is redacted on the way
  /// out. One flag, one purge, one re-download of covers.
  static bool get artworkTokenPurgeDone =>
      _box.get('artworkTokenPurgeDone', defaultValue: false) as bool;

  static Future<void> setArtworkTokenPurgeDone() =>
      _box.put('artworkTokenPurgeDone', true);

  // Legacy single skip interval, superseded by the independent forward/back
  // values below. Read-only on purpose: it exists to seed those two for users
  // who set it before they were split, so nothing writes it any more.
  static int get skipIntervalSeconds =>
      (_box.get('skipInterval', defaultValue: 30) as num).toInt();

  // Forward/back skip intervals — independent. Default to the legacy single
  // value so existing users keep their chosen interval on both directions.
  static int get skipForwardSeconds =>
      (_box.get('skipForward', defaultValue: skipIntervalSeconds) as num)
          .toInt();

  static Future<void> setSkipForward(int seconds) =>
      _box.put('skipForward', seconds);

  static int get skipBackwardSeconds =>
      (_box.get('skipBackward', defaultValue: skipIntervalSeconds) as num)
          .toInt();

  static Future<void> setSkipBackward(int seconds) =>
      _box.put('skipBackward', seconds);

  // Smart auto-rewind on resume (seek back proportionally to time away).
  static bool get autoRewindEnabled =>
      _box.get('autoRewind', defaultValue: true) as bool;

  static Future<void> setAutoRewindEnabled(bool v) =>
      _box.put('autoRewind', v);

  // Resume playback when a transient audio interruption (phone call, alarm)
  // ends. Only applies when the system marks resuming as appropriate — never
  // after another media app permanently takes audio focus.
  static bool get resumeAfterInterruption =>
      _box.get('resumeAfterInterruption', defaultValue: true) as bool;

  static Future<void> setResumeAfterInterruption(bool v) =>
      _box.put('resumeAfterInterruption', v);

  // Seek bar range: whole book (default) or just the current chapter — the
  // fine-scrub option for very long books (1 px of a 30 h book ≈ minutes).
  static bool get chapterScrub =>
      _box.get('chapterScrub', defaultValue: false) as bool;

  static Future<void> setChapterScrub(bool v) => _box.put('chapterScrub', v);

  // Start the next book in the collection automatically when one finishes.
  // Default OFF: finishing a book is a moment, not a cue to start another one
  // without being asked.
  static bool get autoPlayNextBook =>
      _box.get('autoPlayNextBook', defaultValue: false) as bool;

  static Future<void> setAutoPlayNextBook(bool v) =>
      _box.put('autoPlayNextBook', v);

  // Restrict downloads to Wi-Fi / unmetered connections.
  static bool get downloadWifiOnly =>
      _box.get('downloadWifiOnly', defaultValue: false) as bool;

  static Future<void> setDownloadWifiOnly(bool v) =>
      _box.put('downloadWifiOnly', v);

  // Now-playing mark animation: 0 = reactive, 1 = gentle, 2 = pause bars.
  static int get markMotionIndex =>
      (_box.get('markMotion', defaultValue: 0) as num).toInt();

  static Future<void> setMarkMotionIndex(int i) => _box.put('markMotion', i);

  // Reactive animation sync delay in ms (0 = off). Compensates for Bluetooth
  // A2DP latency so the bars stay in sync with what the user hears.
  static int get animationSyncDelayMs =>
      (_box.get('animationSyncDelay', defaultValue: 0) as num).toInt();

  static Future<void> setAnimationSyncDelayMs(int ms) =>
      _box.put('animationSyncDelay', ms);

  static double get defaultSpeed =>
      (_box.get('defaultSpeed', defaultValue: 1.0) as num).toDouble();

  static Future<void> setDefaultSpeed(double speed) =>
      _box.put('defaultSpeed', speed);

  // Default sleep timer: 0 = off, -1 = end of chapter, positive = minutes.
  static int get defaultSleepTimerMinutes =>
      (_box.get('defaultSleepTimer', defaultValue: 0) as num).toInt();

  static Future<void> setDefaultSleepTimerMinutes(int minutes) =>
      _box.put('defaultSleepTimer', minutes);

  // 0 = ink, 1 = cream, 2 = terra, 3 = onyx
  static int get themeIndex =>
      (_box.get('themeIndex', defaultValue: 0) as num).toInt();

  static Future<void> setThemeIndex(int index) =>
      _box.put('themeIndex', index);

  // Per-book, so the key goes through ServerScope like every per-book store —
  // otherwise a second server's book 12345 plays at (and overwrites) the first
  // server's saved speed.
  static double getBookSpeed(String bookRatingKey) =>
      (_box.get('speed_${ServerScope.key(bookRatingKey)}',
              defaultValue: defaultSpeed) as num)
          .toDouble();

  static Future<void> setBookSpeed(String bookRatingKey, double speed) =>
      _box.put('speed_${ServerScope.key(bookRatingKey)}', speed);

  static String? get selectedLibraryKey =>
      _box.get('selectedLibraryKey') as String?;

  static Future<void> setSelectedLibraryKey(String? key) async {
    if (key == null) {
      await _box.delete('selectedLibraryKey');
    } else {
      await _box.put('selectedLibraryKey', key);
    }
  }

  // Opt-in launch-time update check (one GET to api.github.com when enabled).
  // Default OFF — the no-background-network principle; the user opts in.
  static bool get updateCheckEnabled =>
      _box.get('updateCheck', defaultValue: false) as bool;

  static Future<void> setUpdateCheckEnabled(bool v) =>
      _box.put('updateCheck', v);

  // Mask server address in Settings for screenshots/recordings.
  static bool get redactServerAddress =>
      _box.get('redactServerAddress', defaultValue: false) as bool;

  static Future<void> setRedactServerAddress(bool v) =>
      _box.put('redactServerAddress', v);

  static bool get upNextNudgeDismissed =>
      _box.get('upNextNudgeDismissed', defaultValue: false) as bool;

  static Future<void> setUpNextNudgeDismissed(bool v) =>
      _box.put('upNextNudgeDismissed', v);

  static List<String>? getCollectionOrder(String collectionRatingKey) {
    final raw = _box.get('col_order_$collectionRatingKey') as String?;
    if (raw == null) return null;
    return (jsonDecode(raw) as List<dynamic>).cast<String>();
  }

  static Future<void> setCollectionOrder(
      String collectionRatingKey, List<String> order) {
    return _box.put('col_order_$collectionRatingKey', jsonEncode(order));
  }
}
