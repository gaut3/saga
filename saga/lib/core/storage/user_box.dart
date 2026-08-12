import 'package:hive_flutter/hive_flutter.dart';

import '../diagnostics/app_log.dart';

/// Opens a box of user data — the kind that cannot be re-derived if lost.
///
/// Wipes and recreates only on decryption/corruption failures (wrong key on
/// first run after a re-install). Anything else — I/O errors, a truncated file
/// from an unclean OS kill — is rethrown so startup surfaces a real error
/// instead of silently deleting positions, history or bookmarks over a
/// transient failure. This was [BookmarkStore.init]'s behaviour alone while
/// every other user-data box wiped on any `HiveError`; one function so the
/// stores can't drift apart again.
///
/// Derived caches (chapters, cached tracks, book metadata, the timeline queue)
/// keep the simpler wipe-on-any-error open — their contents re-fetch.
Future<Box> openUserBox(String name, List<int> encKey) async {
  final cipher = HiveAesCipher(encKey);
  try {
    return await Hive.openBox(name, encryptionCipher: cipher);
  } on HiveError catch (e) {
    final msg = e.message.toLowerCase();
    if (!msg.contains('wrong key') && !msg.contains('corrupt')) {
      AppLog.log('storage', '$name box failed to open (kept): $e');
      rethrow;
    }
    // The most destructive decision in the app — it must leave a trace.
    AppLog.log('storage', '$name box wiped after decryption failure: $e');
    await Hive.deleteBoxFromDisk(name);
    return Hive.openBox(name, encryptionCipher: cipher);
  }
}

/// Opens a derived-cache box — contents re-fetch, so any [HiveError] wipes and
/// recreates. User-data boxes must use [openUserBox] instead. This open was
/// hand-copied in seven stores; one function so they can't drift.
Future<Box> openCacheBox(String name, List<int> encKey) async {
  final cipher = HiveAesCipher(encKey);
  try {
    return await Hive.openBox(name, encryptionCipher: cipher);
  } on HiveError catch (e) {
    // Contents re-fetch, but the wipe still explains symptoms — a wiped track
    // cache is why a downloaded book won't open until the server is back.
    AppLog.log('storage', '$name cache box wiped after open failure: $e');
    await Hive.deleteBoxFromDisk(name);
    return Hive.openBox(name, encryptionCipher: cipher);
  }
}

/// Caps a decoded-entry cache at [max] entries by dropping the oldest (Dart
/// maps keep insertion order). Shared by the stores that memoise box reads.
void rememberCapped<V>(Map<String, V> cache, int max, String key, V value) {
  if (cache.length >= max) cache.remove(cache.keys.first);
  cache[key] = value;
}
