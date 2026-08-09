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
