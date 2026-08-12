import 'book_progress.dart';
import 'plex/models/plex_book.dart';
import 'storage/book_download_store.dart';
import 'storage/book_metadata_store.dart';
import 'storage/bookmark_store.dart';
import 'storage/completed_books_store.dart';
import 'storage/track_cache_store.dart';

/// What Saga can show with no server: the books already described on the phone.
///
/// Android Auto has always worked this way — its whole browse tree is built
/// from these stores, which is why a downloaded book plays in the car with the
/// server out of reach. The phone's own screens were built the other way
/// round, entirely on the library listing, so the app that could play your
/// downloads in a car could not play them on a plane. This file is the one
/// implementation both now use.
///
/// It is also the seam a local-file library would arrive through: nothing here
/// asks who the book came from, only what is known about it locally.

/// A book assembled from local records, or null when it can't even be named.
///
/// Two sources, because they fill at different times: [BookMetadataStore] holds
/// the full record but only for books whose detail screen has been opened,
/// while [TrackCacheStore] is written for anything downloaded. A book grabbed
/// straight from a list and downloaded has the second and not the first, so
/// the track's own tags name it.
///
/// A book with no name at all is dropped rather than shown as "Unknown" — an
/// unlabelled row is not worth a tap.
PlexBook? localBook(String bookRatingKey) {
  final meta = BookMetadataStore.load(bookRatingKey);
  final tracks = TrackCacheStore.load(bookRatingKey);

  var title = meta?.title;
  var author = meta?.authorName;
  var thumb = meta?.thumbPath;
  if ((title == null || title.isEmpty) && tracks != null && tracks.isNotEmpty) {
    final first = tracks.first;
    title = first.bookTitle;
    author ??= first.authorName;
    thumb ??= first.thumbPath;
  }
  if (title == null || title.isEmpty) return null;

  // Length through the one shared rule (Plex's figure only when it's real,
  // else the length the saved position recorded), with the cached tracks' sum
  // as a last resort — the only one of the three that exists for a book
  // downloaded and never opened.
  final trackSumMs = (tracks == null || tracks.isEmpty)
      ? null
      : tracks.fold<int>(0, (sum, t) => sum + t.durationMs);
  final durationMs = pickTotalDurationMs(
        meta?.totalDurationMs,
        BookmarkStore.load(bookRatingKey)?.totalDurationMs,
      ) ??
      ((trackSumMs != null && trackSumMs > 0) ? trackSumMs : null);

  return PlexBook(
    ratingKey: bookRatingKey,
    title: title,
    authorName: author,
    thumbPath: thumb,
    totalDurationMs: durationMs,
    year: meta?.year,
    leafCount: meta?.leafCount,
    summary: meta?.summary,
    studio: meta?.studio,
    collectionTags: meta?.collectionTags ?? const [],
    seriesIndex: meta?.seriesIndex,
    sortTitle: meta?.sortTitle,
    narrators: meta?.narrators ?? const [],
    genres: meta?.genres ?? const [],
  );
}

/// Book keys with a saved position, newest first, finished books excluded.
///
/// The completed filter is not optional: finishing a book saves a position at
/// the very end, so without it every "continue" surface leads with the book
/// you just finished and "resuming" replays its last few seconds.
List<String> localInProgressKeys() {
  final positions = BookmarkStore.allPositions();
  final completed = CompletedBooksStore.allCompleted();
  return [
    for (final key in positions.keys)
      if (!completed.contains(key)) key,
  ]..sort((a, b) => positions[b]!.savedAt.compareTo(positions[a]!.savedAt));
}

/// Downloaded book keys, alphabetical by title — a shelf, not a history.
List<String> localDownloadedKeys() {
  final books = localBooks(BookDownloadStore.booksWithDownloads());
  books.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  return [for (final b in books) b.ratingKey];
}

/// [localBook] over a list of keys, dropping the ones that can't be named.
List<PlexBook> localBooks(Iterable<String> bookRatingKeys) => [
      for (final key in bookRatingKeys)
        if (localBook(key) case final book?) book,
    ];
