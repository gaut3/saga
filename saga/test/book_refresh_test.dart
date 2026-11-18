import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saga/core/audio/m4b_chapter_reader.dart';
import 'package:saga/core/book_refresh.dart';
import 'package:saga/core/plex/models/plex_track.dart';
import 'package:saga/core/storage/book_download_store.dart';
import 'package:saga/core/storage/book_metadata_store.dart';
import 'package:saga/core/storage/bookmark_store.dart';
import 'package:saga/core/storage/chapter_store.dart';
import 'package:saga/core/storage/download_store.dart';
import 'package:saga/core/storage/server_scope.dart';
import 'package:saga/core/storage/settings_store.dart';
import 'package:saga/core/storage/track_cache_store.dart';

import 'helpers/hive_test_env.dart';

/// Refresh from server (GitHub #28): a book's record, file list and chapters
/// were stored on first open and never asked for again, so chapter titles
/// corrected on the server never showed.
///
/// The rule under test: fetch first, replace only with an answer. A refresh
/// that fails must leave the book exactly as it was.
void main() {
  late Directory dir;

  setUp(() async {
    dir = await startHiveTestEnv();
    ServerScope.debugReset();
    await SettingsStore.init(testEncKey);
    await BookmarkStore.init(testEncKey);
    await BookMetadataStore.init(testEncKey);
    await ChapterStore.init(testEncKey);
    await TrackCacheStore.init(testEncKey);
    await BookDownloadStore.init(testEncKey);
    await DownloadStore.init(testEncKey, documentsDir: dir.path);
  });
  tearDown(() => stopHiveTestEnv(dir));

  PlexTrack track(String rk, {String title = 'Track'}) => PlexTrack(
        ratingKey: rk,
        key: '/library/metadata/$rk',
        title: title,
        durationMs: 60000,
        index: 1,
        partKey: '/library/parts/$rk/file.m4b',
      );

  Map<String, dynamic> record(String title) =>
      {'ratingKey': '10', 'title': title, 'type': 'album'};

  const generic = [
    M4bChapter(title: 'Chapter 01', start: Duration.zero),
    M4bChapter(title: 'Chapter 02', start: Duration(minutes: 10)),
  ];
  const named = [
    M4bChapter(title: 'The Boy Who Lived', start: Duration.zero),
    M4bChapter(title: 'The Vanishing Glass', start: Duration(minutes: 10)),
  ];

  Future<BookRefreshResult> refresh({
    Map<String, dynamic>? Function()? metadata,
    List<PlexTrack> Function()? tracks,
    List<M4bChapter> Function()? chapters,
  }) =>
      refreshBook(
        bookRatingKey: '10',
        fetchMetadata: (_) async => (metadata ?? () => record('New'))(),
        fetchTracks: (_) async => (tracks ?? () => [track('11')])(),
        readChapters: (_) async => (chapters ?? () => named)(),
      );

  test('replaces the stored record and chapters with the server\'s', () async {
    await BookMetadataStore.save('10', record('Old'));
    await ChapterStore.save('11', generic);

    expect(await refresh(), BookRefreshResult.refreshed);

    expect(BookMetadataStore.load('10')!.title, 'New');
    expect(ChapterStore.load('11')!.first.title, 'The Boy Who Lived');
  });

  test('an unreachable server changes nothing', () async {
    await BookMetadataStore.save('10', record('Old'));
    await ChapterStore.save('11', generic);

    final result = await refresh(metadata: () => throw Exception('offline'));

    expect(result, BookRefreshResult.unreachable);
    expect(BookMetadataStore.load('10')!.title, 'Old');
    expect(ChapterStore.load('11')!.first.title, 'Chapter 01');
  });

  test('chapters that cannot be read keep the stored ones', () async {
    // The player resolves the chapter from the store on every tick: a
    // refresh must never empty it for a book that had chapters.
    await ChapterStore.save('11', generic);

    await refresh(chapters: () => const []);
    expect(ChapterStore.load('11')!.length, 2);

    await refresh(chapters: () => throw Exception('read failed'));
    expect(ChapterStore.load('11')!.length, 2);
  });

  test('a failed file list still refreshes the record', () async {
    final result = await refresh(tracks: () => throw Exception('timeout'));
    expect(result, BookRefreshResult.refreshed);
    expect(BookMetadataStore.load('10')!.title, 'New');
  });

  group('a downloaded book', () {
    Future<void> download(String trackKey) async {
      final file = File('${dir.path}/$trackKey.m4b')..writeAsBytesSync([0]);
      await DownloadStore.save(trackKey, file.path);
      BookDownloadStore.recordDownload('10', trackKey);
    }

    test('says its chapters come from the copy on the phone', () async {
      await TrackCacheStore.save('10', [track('11')]);
      await download('11');
      expect(await refresh(), BookRefreshResult.refreshedDownloaded);
    });

    test('takes new track titles while the files are the same', () async {
      await TrackCacheStore.save(
          '10', [track('11', title: 'Old 1'), track('12', title: 'Old 2')]);
      await download('11');
      await download('12');

      await refresh(
          tracks: () =>
              [track('11', title: 'New 1'), track('12', title: 'New 2')]);

      expect(TrackCacheStore.load('10')!.map((t) => t.title),
          ['New 1', 'New 2']);
    });

    test('keeps its file list when the server\'s ids have changed', () async {
      // The files on the phone are named by the old ids. Storing the new
      // list would leave a downloaded book that can't find its own files.
      await TrackCacheStore.save('10', [track('11'), track('12')]);
      await download('11');
      await download('12');

      await refresh(tracks: () => [track('21'), track('22')]);

      expect(TrackCacheStore.load('10')!.map((t) => t.ratingKey), ['11', '12']);
    });
  });
}
