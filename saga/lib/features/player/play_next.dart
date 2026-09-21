import '../../core/diagnostics/app_log.dart';
import '../../core/plex/models/plex_book.dart';
import '../../core/plex/models/plex_track.dart';
import '../../core/storage/bookmark_store.dart';
import '../../core/storage/settings_store.dart';
import 'book_launch.dart';
import 'player_service.dart';

/// How close to the end a saved position must sit to count as the artifact a
/// finish leaves behind rather than a place worth resuming.
const _endOfBookMarginMs = 10000;

/// Whether [saved] is a real mid-book place — not absent, not the end-of-book
/// position a finish writes. The advance resumes only these: "resuming" an
/// end-of-book bookmark replays the final second, completes again, and — with
/// auto-play on — cascades an advance through every finished book after it.
/// One rule, shared by [playNextBook] and the finished panel's buttons, so
/// what the panel offers and what the advance does can't disagree.
bool isResumablePosition(BookPosition? saved) {
  if (saved == null) return false;
  if (saved.absolutePositionMs <= 0) return false;
  final total = saved.totalDurationMs;
  // Unknown length: can't tell the end from the middle — resume, the choice
  // that never discards a real place.
  if (total == null || total <= 0) return true;
  return total - saved.absolutePositionMs > _endOfBookMarginMs;
}

/// Loads [book] and starts playing it.
///
/// The single path for "move on to the next book" — the finished panel's button
/// and the automatic advance both come through here, so the two can't drift
/// apart. The launch itself belongs to [startBook]; all this adds is the
/// choice of start point. Left unspecified, it follows the book's bookmark
/// ([isResumablePosition]): a real mid-book place is resumed — the unattended
/// advance must never destroy one — while no place, or the end-of-book
/// artifact of an earlier finish, starts from the beginning, which is what a
/// series listened to anew needs at every handoff. The finished panel passes
/// [from] explicitly when the user makes the call ("Start over").
///
/// Takes [loadTracks] rather than a ref because the two callers hold different
/// ref types (`WidgetRef` in the panel, `Ref` in the provider) and Riverpod 2
/// gives them no common supertype.
///
/// Returns false if it couldn't start; the caller decides whether that deserves
/// a message.
Future<bool> playNextBook({
  required AudioPlayerService service,
  required PlexBook book,
  required Future<List<PlexTrack>> Function(String bookRatingKey) loadTracks,
  BookStartPoint? from,
}) async {
  from ??= isResumablePosition(BookmarkStore.load(book.ratingKey))
      ? const BookStartPoint.resume()
      : const BookStartPoint.beginning();
  var speedCopied = false;
  try {
    final tracks = await loadTracks(book.ratingKey);
    if (tracks.isEmpty) return false;
    // A next book with no speed of its own follows the book it came after —
    // this path only runs inside a collection, where the next book usually
    // shares the narrator — instead of dropping to the default. Written once,
    // so its own speed wins permanently the moment the user sets one; and only
    // copied from an *explicit* speed, so books riding the global default keep
    // following that setting. Written after the track fetch (and rolled back
    // on a failed start) so an advance that never starts the book doesn't
    // permanently stamp it.
    final prevKey = service.currentBookRatingKey;
    if (prevKey != null &&
        SettingsStore.hasBookSpeed(prevKey) &&
        !SettingsStore.hasBookSpeed(book.ratingKey)) {
      await SettingsStore.setBookSpeed(
          book.ratingKey, SettingsStore.getBookSpeed(prevKey));
      speedCopied = true;
    }
    final started = await startBook(
      service: service,
      bookRatingKey: book.ratingKey,
      tracks: tracks,
      from: from,
    );
    if (!started && speedCopied) {
      await SettingsStore.removeBookSpeed(book.ratingKey);
    }
    return started;
  } catch (e) {
    if (speedCopied) await SettingsStore.removeBookSpeed(book.ratingKey);
    AppLog.log('playback', 'play next failed for ${book.ratingKey}: $e');
    return false;
  }
}
