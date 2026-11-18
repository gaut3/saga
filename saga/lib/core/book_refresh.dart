/// Fetching again what Saga keeps about a book: its record, its file list
/// and a single-file book's embedded chapters.
///
/// All three are stored the first time a book is opened and were never asked
/// for again, so a book corrected on the server (new chapter titles, a fixed
/// narrator) kept showing what it had on first open (GitHub #28).
///
/// The rule throughout: fetch first, replace only with an answer. A refresh
/// with the server out of reach, or of a file whose chapters can't be read,
/// leaves what was stored. The player reads stored chapters on every position
/// tick, so nothing is deleted to make room for the new copy.
library;

import 'audio/m4b_chapter_reader.dart';
import 'diagnostics/app_log.dart';
import 'plex/models/plex_track.dart';
import 'plex/plex_client.dart';
import 'storage/book_download_store.dart';
import 'storage/book_metadata_store.dart';
import 'storage/chapter_store.dart';
import 'storage/track_cache_store.dart';

enum BookRefreshResult {
  /// The server didn't answer. Nothing was changed.
  unreachable,

  /// The book's details were fetched again.
  refreshed,

  /// As [refreshed], but the book is one downloaded file: its chapters come
  /// from the copy on the phone, which a refresh can't replace.
  refreshedDownloaded,
}

/// Reads [trackRatingKey]'s chapters with [read] and stores them over the old
/// ones. Returns whether there was anything to store. Never throws.
Future<bool> rereadChapters(String trackRatingKey,
    Future<List<M4bChapter>> Function() read) async {
  try {
    final chapters = await read();
    if (chapters.isEmpty) return false;
    await ChapterStore.save(trackRatingKey, chapters);
    return true;
  } catch (e) {
    AppLog.log('chapters', 're-read failed for $trackRatingKey: $e');
    return false;
  }
}

/// Fetches [bookRatingKey]'s record, file list and chapters again.
///
/// The caller invalidates the providers that hold the old values. The
/// fetchers are parameters so the rules here can be tested without a server.
Future<BookRefreshResult> refreshBook({
  required String bookRatingKey,
  required Future<Map<String, dynamic>?> Function(String) fetchMetadata,
  required Future<List<PlexTrack>> Function(String) fetchTracks,
  required Future<List<M4bChapter>> Function(PlexTrack track) readChapters,
}) async {
  final Map<String, dynamic>? raw;
  try {
    raw = await fetchMetadata(bookRatingKey);
  } catch (e) {
    AppLog.log('plex', 'refresh: metadata fetch failed for $bookRatingKey: $e');
    return BookRefreshResult.unreachable;
  }
  if (raw == null) return BookRefreshResult.unreachable;
  await BookMetadataStore.save(bookRatingKey, raw);

  var tracks = TrackCacheStore.load(bookRatingKey) ?? const <PlexTrack>[];
  try {
    final fresh = await fetchTracks(bookRatingKey);
    if (fresh.isNotEmpty) {
      // The stored list is what makes a downloaded book open offline, and
      // the files on the phone are named by its track ids. It takes the
      // server's titles only while the ids still match: a book re-added
      // under new ids keeps its old list until it is downloaded again.
      final sameFiles = tracks.isEmpty ||
          _keys(tracks).containsAll(_keys(fresh)) &&
              tracks.length == fresh.length;
      if (BookDownloadStore.hasDownload(bookRatingKey) && sameFiles) {
        await TrackCacheStore.save(bookRatingKey, fresh);
      }
      tracks = fresh;
    }
  } catch (e) {
    AppLog.log('plex', 'refresh: tracks fetch failed for $bookRatingKey: $e');
  }

  // Embedded chapters only exist for a single-file book; a book of many
  // files shows its track titles, refreshed above.
  if (tracks.length != 1) return BookRefreshResult.refreshed;
  final track = tracks.single;
  final downloaded = PlexClient.localTrackPath(track) != null;
  await rereadChapters(track.ratingKey, () => readChapters(track));
  return downloaded
      ? BookRefreshResult.refreshedDownloaded
      : BookRefreshResult.refreshed;
}

Set<String> _keys(List<PlexTrack> tracks) =>
    {for (final t in tracks) t.ratingKey};
