import 'book_metadata_store.dart';
import 'chapter_store.dart';
import 'settings_store.dart';

/// Namespaces per-book storage keys by the Plex server the book lives on.
///
/// A Plex `ratingKey` is an integer that is only unique **within one server**.
/// Every store here keys by it — positions, completions, cached tracks,
/// downloads, chapters — so two servers both having a book 12345 means the
/// second one silently inherits the first one's data. Plex lists servers other
/// people have shared with you alongside your own, so "I have my library and a
/// friend's" is an ordinary setup, not an exotic one, and switching between
/// them is two taps.
///
/// What that looks like: a book you have never opened sitting four hours in, a
/// cover and author belonging to a different book, or a downloaded file played
/// for the wrong entry. The first of those is losing someone's place, which is
/// the one thing this app is not allowed to do.
///
/// ## Why the first server keeps unprefixed keys
///
/// The obvious fix — prefix every key with the server id — would require
/// rewriting every existing record on upgrade. A migration that walks the
/// positions box is exactly the operation that can lose positions, to fix a
/// problem that only bites people with a second server.
///
/// So the first server the app ever sees keeps writing bare keys, and only a
/// *different* server gets a prefix. Existing installs are untouched: no
/// migration, no rewrite, and for anyone who never adds a second server the
/// keys are byte-identical to what they have today. The cost is one branch.
class ServerScope {
  ServerScope._();

  static const _separator = '|';

  static String? _current;
  static String? _primary;

  /// Points the scope at [serverId] (a Plex `machineIdentifier`), remembering
  /// the first one ever seen as the primary.
  ///
  /// Call on startup once the client has loaded, and again whenever the
  /// selected server changes. Passing null (signed out) falls back to the
  /// *last active* server's keys — a signed-out user still playing downloaded
  /// books should see the library those downloads came from, which is not
  /// necessarily the primary. With nothing recorded (a fresh install) the
  /// scope stays null, which reads as primary/bare.
  static Future<void> configure(String? serverId) async {
    serverId ??= SettingsStore.lastServerId;
    final changed = serverId != _current;
    _current = serverId;
    _primary = SettingsStore.primaryServerId;
    if (serverId != null) {
      if (_primary == null) {
        _primary = serverId;
        await SettingsStore.setPrimaryServerId(serverId);
      }
      await SettingsStore.setLastServerId(serverId);
    }
    // The stores' decoded in-memory caches are keyed by *bare* rating key, so
    // they outlive a re-point of the scope and would serve the previous
    // server's records for the new server's same-numbered keys.
    if (changed) {
      BookMetadataStore.clearDecodedCache();
      ChapterStore.clearDecodedCache();
    }
  }

  /// Resets in-memory state. Tests only — real callers use [configure].
  static void debugReset() {
    _current = null;
    _primary = null;
  }

  /// True when the current server writes unprefixed keys.
  static bool get _isPrimary => _current == null || _current == _primary;

  /// The storage key to file [ratingKey] under.
  static String key(String ratingKey) =>
      _isPrimary ? ratingKey : '$_current$_separator$ratingKey';

  /// Same as [key], for stores that build a compound key of their own
  /// (`log_<ratingKey>`): scope the whole thing, prefix included.
  static String prefixed(String prefix, String ratingKey) =>
      key('$prefix$ratingKey');

  /// The rating key inside [storageKey], or **null when it belongs to another
  /// server** — which is what makes listing a box skip foreign records instead
  /// of showing them as if they were this server's.
  ///
  /// Records written before any of this existed have no prefix and belong to
  /// the primary server, which is where they were written.
  static String? ratingKeyOf(String storageKey) {
    final split = storageKey.indexOf(_separator);
    if (split < 0) return _isPrimary ? storageKey : null;
    final owner = storageKey.substring(0, split);
    return owner == _current ? storageKey.substring(split + 1) : null;
  }

  /// Strips [prefix] from a scoped compound key, or null if the key isn't this
  /// server's or doesn't carry that prefix.
  static String? unprefixed(String prefix, String storageKey) {
    final ratingKey = ratingKeyOf(storageKey);
    if (ratingKey == null || !ratingKey.startsWith(prefix)) return null;
    return ratingKey.substring(prefix.length);
  }
}
