import 'package:hive_flutter/hive_flutter.dart';

import '../diagnostics/app_log.dart';

/// Opens a box of user data — the kind that cannot be re-derived if lost.
///
/// Wipes and recreates only when Hive itself reports a wrong key or
/// corruption. Anything else (an I/O error, a lock) is rethrown so startup
/// surfaces a real error instead of silently deleting positions, history or
/// bookmarks over a transient failure. One function so the stores can't
/// drift apart.
///
/// What this does not catch: Hive rarely throws for either case. A frame that
/// fails its checksum (a torn write, or every frame under a wrong key) is
/// taken for crash damage and the file is truncated there, silently. A torn
/// last frame after a kill is the case that recovery exists for. The
/// wrong-key case is kept out at the door instead: `loadHiveKey` never hands
/// a new key to an install that already has boxes.
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

/// Holds a cache box to [max] entries: once over, deletes entries whose key
/// isn't in [keep] until it is back at the limit. A cache that writes per
/// book and never deletes grows for as long as the app is installed, and a
/// Hive box is read into memory whole at every start.
///
/// Hive orders keys by value, not by age, so which unkept entries go is
/// arbitrary. That is fine for a cache: each one re-fetches when its book is
/// next opened. [keep] is for the entries that can't (the book in hand, books
/// with a place or a download, which must still open with no server).
///
/// [keep] is only asked once the box is over the limit.
Future<int> evictOver(Box box, int max, Set<String> Function() keep) async {
  final excess = box.length - max;
  if (excess <= 0) return 0;
  final kept = keep();
  final doomed = [
    for (final k in box.keys)
      if (!kept.contains(k.toString())) k,
  ].take(excess).toList();
  await box.deleteAll(doomed);
  return doomed.length;
}

/// Caps a decoded-entry cache at [max] entries by dropping the oldest (Dart
/// maps keep insertion order). Shared by the stores that memoise box reads.
void rememberCapped<V>(Map<String, V> cache, int max, String key, V value) {
  if (cache.length >= max) cache.remove(cache.keys.first);
  cache[key] = value;
}
