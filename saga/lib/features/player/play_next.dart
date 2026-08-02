import '../../core/diagnostics/app_log.dart';
import '../../core/plex/models/plex_book.dart';
import '../../core/plex/models/plex_track.dart';
import '../../core/storage/settings_store.dart';
import 'player_service.dart';

/// Loads [book] and starts playing it.
///
/// The single path for "move on to the next book" — the finished panel's button
/// and the automatic advance both come through here, so the two can't drift
/// apart (speed applied before the load, `playWhenReady` set, and resume rewind
/// deliberately absent because a next book is by definition unstarted).
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
    // Speed before load: with playWhenReady, audio can start the instant
    // buffering completes — it must already be at the book's saved speed.
    await service.setSpeed(SettingsStore.getBookSpeed(book.ratingKey));
    await service.loadBook(
      bookRatingKey: book.ratingKey,
      tracks: tracks,
      playWhenReady: true,
    );
    await service.play();
    return true;
  } catch (e) {
    AppLog.log('playback', 'play next failed for ${book.ratingKey}: $e');
    return false;
  }
}
