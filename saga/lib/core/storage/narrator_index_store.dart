import 'package:hive_flutter/hive_flutter.dart';

import 'server_scope.dart';

const _boxName = 'narrator_index';

/// Book → narrators for a whole library section.
///
/// Narrator lives in Plex's `Style`, which the library listing doesn't carry,
/// so sorting and searching by it needs a lookup built ahead of time. Built
/// once from the Style endpoints and kept, because it changes only when the
/// library does.
class NarratorIndexStore {
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

  // Section keys are per-server integers like rating keys, so they go through
  // ServerScope too: both servers having a section "1" must not share (or
  // destroy) each other's index.
  static String _key(String sectionKey) =>
      'idx_${ServerScope.key(sectionKey)}';
  static String _stampKey(String sectionKey) =>
      'built_${ServerScope.key(sectionKey)}';

  /// The section's index, or null if it has never been built.
  static Map<String, List<String>>? load(String sectionKey) {
    final raw = _box.get(_key(sectionKey));
    if (raw == null) return null;
    try {
      return {
        for (final e in (raw as Map).entries)
          e.key.toString(): (e.value as List<dynamic>)
              .map((v) => v.toString())
              .toList(),
      };
    } catch (_) {
      // Malformed entry — treat as never built rather than crashing the caller.
      return null;
    }
  }

  static Future<void> save(
      String sectionKey, Map<String, List<String>> index) async {
    await _box.put(_key(sectionKey), index);
    await _box.put(_stampKey(sectionKey), DateTime.now().toIso8601String());
  }

  /// When the section was last indexed, for offering a refresh.
  static DateTime? builtAt(String sectionKey) {
    final raw = _box.get(_stampKey(sectionKey));
    return raw == null ? null : DateTime.tryParse(raw.toString());
  }

  static bool has(String sectionKey) => _box.containsKey(_key(sectionKey));

  static Future<void> clear(String sectionKey) async {
    await _box.delete(_key(sectionKey));
    await _box.delete(_stampKey(sectionKey));
  }
}

/// Inverts narrator → books into book → narrators.
///
/// Plex answers "which books does this narrator read", but sorting a book list
/// needs the opposite. Pulled out as a pure function so the shape that matters
/// — a book with two narrators, a narrator with no books — is testable without
/// a server.
///
/// Narrators are kept in the order the tags were listed, and de-duplicated: a
/// book tagged with the same narrator twice must not read "X, X".
Map<String, List<String>> invertNarratorIndex(
    List<({String narrator, List<String> bookKeys})> byNarrator) {
  final out = <String, List<String>>{};
  for (final entry in byNarrator) {
    if (entry.narrator.isEmpty) continue;
    for (final bookKey in entry.bookKeys) {
      final list = out.putIfAbsent(bookKey, () => <String>[]);
      if (!list.contains(entry.narrator)) list.add(entry.narrator);
    }
  }
  return out;
}
