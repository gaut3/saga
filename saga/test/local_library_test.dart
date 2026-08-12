import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saga/core/local_library.dart';
import 'package:saga/core/plex/models/plex_track.dart';
import 'package:saga/core/storage/book_download_store.dart';
import 'package:saga/core/storage/book_metadata_store.dart';
import 'package:saga/core/storage/bookmark_store.dart';
import 'package:saga/core/storage/completed_books_store.dart';
import 'package:saga/core/storage/server_scope.dart';
import 'package:saga/core/storage/settings_store.dart';
import 'package:saga/core/storage/track_cache_store.dart';

import 'helpers/hive_test_env.dart';

/// The books Saga can name and play with no server.
///
/// This rule used to live only inside `media_browse.dart`, so Android Auto
/// could list a downloaded book that the phone's own Home screen could not —
/// Home was built entirely on the library listing, and an offline launch ended
/// on a "Connect to Plex" screen with the downloads sitting unreachable behind
/// it. Both surfaces now read from here, so the car and the phone cannot
/// disagree about what is playable offline.
void main() {
  late Directory dir;

  setUp(() async {
    dir = await startHiveTestEnv();
    ServerScope.debugReset();
    await SettingsStore.init(testEncKey);
    await BookmarkStore.init(testEncKey);
    await BookMetadataStore.init(testEncKey);
    await CompletedBooksStore.init(testEncKey);
    await TrackCacheStore.init(testEncKey);
    await BookDownloadStore.init(testEncKey);
  });
  tearDown(() => stopHiveTestEnv(dir));

  PlexTrack track(
    String rk, {
    String? bookTitle,
    String? author,
    int durationMs = 60000,
  }) =>
      PlexTrack(
        ratingKey: rk,
        key: '/library/metadata/$rk',
        title: 'Track $rk',
        durationMs: durationMs,
        index: 1,
        partKey: '/library/parts/$rk',
        bookTitle: bookTitle,
        authorName: author,
      );

  BookPosition posAt(int ms, {DateTime? savedAt, int? totalMs}) => BookPosition(
        trackRatingKey: 't1',
        positionMs: ms,
        absolutePositionMs: ms,
        savedAt: savedAt ?? DateTime(2026, 8, 11),
        totalDurationMs: totalMs,
      );

  group('naming a book from local records only', () {
    test('a downloaded book never opened is named by its cached tracks',
        () async {
      // The exact gap that made offline Home impossible: BookMetadataStore is
      // only written when a book's *detail screen* is opened, so a book
      // grabbed from a list and downloaded has no record there at all.
      await TrackCacheStore.save('12345', [
        track('t1', bookTitle: 'The Blade Itself', author: 'Joe Abercrombie'),
        track('t2'),
      ]);

      final book = localBook('12345');
      expect(book, isNotNull);
      expect(book!.title, 'The Blade Itself');
      expect(book.authorName, 'Joe Abercrombie');
      expect(book.ratingKey, '12345');
    });

    test('a book with no name anywhere is dropped, not called "Unknown"',
        () async {
      await TrackCacheStore.save('12345', [track('t1')]); // no bookTitle
      expect(localBook('12345'), isNull);
    });

    test('length falls back to the cached tracks when nothing else knows it',
        () async {
      await TrackCacheStore.save('12345', [
        track('t1', bookTitle: 'A Book', durationMs: 90000),
        track('t2', durationMs: 30000),
      ]);
      expect(localBook('12345')?.totalDurationMs, 120000);
    });

    test('a length the position recorded beats the track sum', () async {
      await TrackCacheStore.save('12345', [
        track('t1', bookTitle: 'A Book', durationMs: 90000),
      ]);
      await BookmarkStore.save('12345', posAt(1000, totalMs: 500000));
      expect(localBook('12345')?.totalDurationMs, 500000);
    });

    test('an unknown book is null rather than an empty shell', () {
      expect(localBook('nope'), isNull);
    });
  });

  group('what belongs on each shelf', () {
    test('in-progress is newest first and excludes finished books', () async {
      await TrackCacheStore.save('a', [track('t1', bookTitle: 'A')]);
      await TrackCacheStore.save('b', [track('t1', bookTitle: 'B')]);
      await TrackCacheStore.save('c', [track('t1', bookTitle: 'C')]);
      await BookmarkStore.save('a', posAt(10, savedAt: DateTime(2026, 8, 1)));
      await BookmarkStore.save('b', posAt(10, savedAt: DateTime(2026, 8, 9)));
      await BookmarkStore.save('c', posAt(10, savedAt: DateTime(2026, 8, 5)));
      // Finishing a book saves a position at the very end, which would
      // otherwise make it the most recent thing in progress.
      await CompletedBooksStore.markCompleted('b');

      expect(localInProgressKeys(), ['c', 'a']);
    });

    test('downloaded is alphabetical by title, not by rating key', () async {
      await TrackCacheStore.save('90', [track('t1', bookTitle: 'Anathem')]);
      await TrackCacheStore.save('10', [track('t1', bookTitle: 'Zone One')]);
      await TrackCacheStore.save('50', [track('t1', bookTitle: 'Mistborn')]);
      for (final k in ['90', '10', '50']) {
        BookDownloadStore.recordDownload(k, 't1');
      }

      expect(
        [for (final b in localBooks(localDownloadedKeys())) b.title],
        ['Anathem', 'Mistborn', 'Zone One'],
      );
    });

    test('a downloaded book that cannot be named stays off the shelf',
        () async {
      await TrackCacheStore.save('12345', [track('t1')]); // nameless
      BookDownloadStore.recordDownload('12345', 't1');
      expect(localDownloadedKeys(), isEmpty);
    });
  });

  test('the local shelves survive a cold restart', () async {
    await TrackCacheStore.save('12345', [
      track('t1', bookTitle: 'Piranesi', author: 'Susanna Clarke'),
    ]);
    BookDownloadStore.recordDownload('12345', 't1');
    await BookmarkStore.save('12345', posAt(60000));

    // Hive hands nested maps back as Map<dynamic, dynamic> on a real cold
    // read, which a stricter parse drops silently — the failure mode would be
    // an empty offline Home on exactly the launch it exists for.
    await coldRestartHive();
    ServerScope.debugReset();
    await SettingsStore.init(testEncKey);
    await BookmarkStore.init(testEncKey);
    await BookMetadataStore.init(testEncKey);
    await CompletedBooksStore.init(testEncKey);
    await TrackCacheStore.init(testEncKey);
    await BookDownloadStore.init(testEncKey);

    expect(localBook('12345')?.title, 'Piranesi');
    expect(localDownloadedKeys(), ['12345']);
    expect(localInProgressKeys(), ['12345']);
  });
}
