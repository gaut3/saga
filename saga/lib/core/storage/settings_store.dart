import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

const _boxName = 'settings';

class SettingsStore {
  static late Box _box;

  static Future<void> init(List<int> encKey) async {
    final cipher = HiveAesCipher(encKey);
    try {
      _box = await Hive.openBox(_boxName, encryptionCipher: cipher);
    } on HiveError {
      await Hive.deleteBoxFromDisk(_boxName);
      _box = await Hive.openBox(_boxName, encryptionCipher: cipher);
    }
  }

  static int get skipIntervalSeconds =>
      (_box.get('skipInterval', defaultValue: 30) as num).toInt();

  static Future<void> setSkipInterval(int seconds) =>
      _box.put('skipInterval', seconds);

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

  // 0 = ink, 1 = cream, 2 = terra
  static int get themeIndex =>
      (_box.get('themeIndex', defaultValue: 0) as num).toInt();

  static Future<void> setThemeIndex(int index) =>
      _box.put('themeIndex', index);

  static double getBookSpeed(String bookRatingKey) =>
      (_box.get('speed_$bookRatingKey', defaultValue: defaultSpeed) as num)
          .toDouble();

  static Future<void> setBookSpeed(String bookRatingKey, double speed) =>
      _box.put('speed_$bookRatingKey', speed);

  static String? get selectedLibraryKey =>
      _box.get('selectedLibraryKey') as String?;

  static Future<void> setSelectedLibraryKey(String? key) async {
    if (key == null) {
      await _box.delete('selectedLibraryKey');
    } else {
      await _box.put('selectedLibraryKey', key);
    }
  }

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
