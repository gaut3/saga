import '../../core/diagnostics/app_log.dart';
import '../../core/plex/models/plex_book.dart';
import '../../core/plex/models/plex_track.dart';
import 'book_launch.dart';
import 'player_service.dart';

/// Loads [book] and starts playing it from the beginning.
///
/// The single path for "move on to the next book" — the finished panel's button
/// and the automatic advance both come through here, so the two can't drift
/// apart. The launch itself belongs to [startBook]; all this adds is the choice
/// of start point, which for a next book is the beginning by definition.
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
}) async {
  try {
    final tracks = await loadTracks(book.ratingKey);
    if (tracks.isEmpty) return false;
    return startBook(
      service: service,
      bookRatingKey: book.ratingKey,
      tracks: tracks,
      from: const BookStartPoint.beginning(),
    );
  } catch (e) {
    AppLog.log('playback', 'play next failed for ${book.ratingKey}: $e');
    return false;
  }
}
