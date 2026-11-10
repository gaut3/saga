import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saga/core/plex/models/plex_track.dart';
import 'package:saga/core/storage/book_download_store.dart';
import 'package:saga/core/storage/book_metadata_store.dart';
import 'package:saga/core/storage/bookmark_store.dart';
import 'package:saga/core/storage/completed_books_store.dart';
import 'package:saga/core/storage/playback_log_store.dart';
import 'package:saga/core/storage/server_scope.dart';
import 'package:saga/core/storage/settings_store.dart';
import 'package:saga/core/storage/track_cache_store.dart';
import 'package:saga/core/theme/saga_theme.dart';
import 'package:saga/core/local_library.dart';
import 'package:saga/features/widget/home_widget_sync.dart';
import 'package:saga/shared/widgets/resume_card.dart';

import 'helpers/hive_test_env.dart';

/// The home-screen widget's snapshot: what it shows, and what it must never
/// carry.
void main() {
  late Directory dir;

  setUp(() async {
    dir = await startHiveTestEnv();
    ServerScope.debugReset();
    await SettingsStore.init(testEncKey);
    await BookmarkStore.init(testEncKey);
    await BookMetadataStore.init(testEncKey);
    await CompletedBooksStore.init(testEncKey);
    await PlaybackLogStore.init(testEncKey);
    await TrackCacheStore.init(testEncKey);
    await BookDownloadStore.init(testEncKey);
  });
  tearDown(() => stopHiveTestEnv(dir));

  PlexTrack track(String rk, String book, {int durationMs = 3600000}) =>
      PlexTrack(
        ratingKey: rk,
        key: '/library/metadata/$rk',
        title: 'Part $rk',
        durationMs: durationMs,
        index: 1,
        partKey: '/library/parts/$rk',
        bookTitle: book,
        authorName: 'Author',
      );

  /// A two-file book, each file an hour, with a saved position [ms] in.
  Future<void> book(String key, String title,
      {required int ms, required DateTime savedAt}) async {
    await TrackCacheStore.save(
        key, [track('${key}a', title), track('${key}b', title)]);
    await BookmarkStore.save(
      key,
      BookPosition(
        trackRatingKey: ms < 3600000 ? '${key}a' : '${key}b',
        positionMs: ms % 3600000,
        absolutePositionMs: ms,
        totalDurationMs: 7200000,
        savedAt: savedAt,
      ),
    );
  }

  test('signed out carries no book at all', () async {
    // The snapshot sits unencrypted beside the app; after sign-out it must
    // not keep naming the account's books on the home screen.
    await book('1', 'Foundation', ms: 600000, savedAt: DateTime(2026, 11, 1));
    final s = widgetSnapshot(signedIn: false);
    expect(s['state'], 'signedOut');
    expect(s.keys.where((k) => !k.startsWith('color')), ['state']);
  });

  test('nothing in progress is the empty state', () {
    final s = widgetSnapshot(signedIn: true);
    expect(s['state'], 'empty');
    expect(s.keys.where((k) => !k.startsWith('color')), ['state']);
  });

  test("wears the stored theme, whatever the app last applied", () async {
    // The headless engine never runs App.build(), so SagaColors would still
    // be Ink there: the widget must read the setting itself.
    await SettingsStore.setThemeIndex(SagaThemeVariant.cream.index);
    final s = widgetSnapshot(signedIn: true);
    expect(s['colorSurface'], SagaThemeData.cream.surface.toARGB32());
    expect(s['colorBar'], SagaThemeData.cream.accent.toARGB32());
    expect(s['colorFooter'], SagaThemeData.cream.accent.toARGB32());

    await SettingsStore.setThemeIndex(SagaThemeVariant.onyx.index);
    // Onyx's footer is accentDim, as on Home's card.
    expect(widgetSnapshot(signedIn: true)['colorFooter'],
        SagaThemeData.onyx.accentDim!.toARGB32());
  });

  test("shows Home's book: newest saved position, finished books left out",
      () async {
    await book('1', 'Older', ms: 600000, savedAt: DateTime(2026, 10, 1));
    await book('2', 'Newest but finished',
        ms: 7199000, savedAt: DateTime(2026, 11, 1));
    await CompletedBooksStore.markCompleted('2');

    final s = widgetSnapshot(signedIn: true);
    expect(s['state'], 'book');
    expect(s['bookKey'], '1');
    expect(s['title'], 'Older');
  });

  test('a loaded book in progress wins: it is what pause acts on', () async {
    await book('1', 'Older', ms: 600000, savedAt: DateTime(2026, 10, 1));
    await book('2', 'Newer', ms: 600000, savedAt: DateTime(2026, 11, 1));

    expect(widgetSnapshot(signedIn: true, loadedBookKey: '1')['bookKey'], '1');
    // Loaded but finished (stop keeps the book loaded): Home's book instead.
    await CompletedBooksStore.markCompleted('1');
    expect(widgetSnapshot(signedIn: true, loadedBookKey: '1')['bookKey'], '2');
  });

  test("the card's figures, formatted for drawing verbatim", () async {
    // 1h 30m into a 2h book, in the second file.
    await book('1', 'Foundation', ms: 5400000, savedAt: DateTime(2026, 11, 1));

    final s = widgetSnapshot(signedIn: true);
    expect(s['timeLeft'], '30m left');
    expect(s['percent'], '75%');
    expect(s['progress'], 750);
    // The title alone, as the player shows it (GitHub #17).
    expect(s['chapter'], 'Part 1b');
    expect(s['skipBack'], SettingsStore.skipBackwardSeconds);
    expect(s['skipForward'], SettingsStore.skipForwardSeconds);
  });

  // GitHub #17: with "Scrub within chapter" on, the widget's figures follow
  // the chapter, as the player's seek bar does. Here the chapter is the file.
  group('in chapter mode', () {
    setUp(() => SettingsStore.setChapterScrub(true));

    test("shows the chapter's time left, % and bar", () async {
      // 1h 30m into the book: 30 min into the second one-hour file.
      await book('1', 'Foundation', ms: 5400000, savedAt: DateTime(2026, 11, 1));

      final s = widgetSnapshot(signedIn: true);
      expect(s['timeLeft'], '30m left in chapter');
      expect(s['percent'], '50%');
      expect(s['progress'], 500);
    });

    test('moves once a minute, not on every 10 s save', () async {
      // Each changed snapshot is a redraw. 29:20 and 29:30 into the chapter
      // are both 29 whole minutes listened, so they must draw the same.
      Future<Map<String, Object?>> at(int ms) async {
        await book('1', 'Foundation',
            ms: 3600000 + ms, savedAt: DateTime(2026, 11, 1));
        return widgetSnapshot(signedIn: true);
      }

      final a = await at(29 * 60000 + 20000);
      final b = await at(29 * 60000 + 30000);
      expect(b['progress'], a['progress']);
      expect(b['timeLeft'], a['timeLeft']);
      expect(a['timeLeft'], '31m left in chapter');
      expect(a['progress'], 483);
    });

    test('a chapter just begun draws an empty bar', () async {
      // Rounding the time left instead drew a fresh chapter partly listened.
      await book('1', 'Foundation',
          ms: 3600000 + 20000, savedAt: DateTime(2026, 11, 1));
      final s = widgetSnapshot(signedIn: true);
      expect(s['progress'], 0);
      expect(s['percent'], '0%');
      expect(s['timeLeft'], '1h 0m left in chapter');
    });
  });

  test('never stores whether a book is playing', () async {
    // A stored "playing" outlives the process that set it: absorb and
    // AntennaPod both shipped a widget stuck on pause over silence.
    await book('1', 'Foundation', ms: 600000, savedAt: DateTime(2026, 11, 1));
    final keys = widgetSnapshot(signedIn: true).keys;
    expect(keys.where((k) => k.toLowerCase().contains('play')), isEmpty);

    final kotlin = File('packages/saga_native/android/src/main/kotlin/'
            'com/gaut3/saga/nativebridge/SagaWidget.kt')
        .readAsStringSync();
    expect(kotlin, isNot(contains('putBoolean("playing"')));
  });

  // The widget followed "Scrub within chapter" and Home's card didn't, so with
  // the setting on one book read "5m left in chapter · 48%" on the home screen
  // and "11h 59m left · 29%" in the app. One function draws both now.
  group("Home's card and the widget show the same figures", () {
    Future<void> check({required bool chapterScrub}) async {
      await SettingsStore.setChapterScrub(chapterScrub);
      await book('1', 'Foundation', ms: 5400000, savedAt: DateTime(2026, 11, 1));
      final s = widgetSnapshot(signedIn: true);
      final card = resumeFigures(localBook('1')!, TrackCacheStore.load('1'),
          BookmarkStore.load('1'),
          chapterScrub: chapterScrub);
      expect(card.timeLeft, s['timeLeft']);
      expect('${(card.fraction * 100).round()}%', s['percent']);
    }

    test('in book mode', () => check(chapterScrub: false));
    test('in chapter mode', () => check(chapterScrub: true));

    test('the card draws from the shared figures and follows the toggle', () {
      final src = File('lib/shared/widgets/resume_card.dart').readAsStringSync();
      final build = src.substring(src.indexOf('Widget build('),
          src.indexOf('Future<void> _openPlayerView'));
      expect(build, contains('resumeFigures('));
      expect(build, contains('ref.watch(chapterScrubProvider)'));
      expect(build, isNot(contains('resumeProgress(')));
    });
  });

  test('the cover is a file path, never a URL', () {
    // Source check: the cover comes from the artwork cache as a file path. A
    // URL is the shape a credential leaks in (see CLAUDE.md, artwork).
    final src =
        File('lib/features/widget/home_widget_sync.dart').readAsStringSync();
    expect(src, contains("'cover': ArtworkCache.getLocalUri("));
    expect(src, contains('?.toFilePath()'));
    expect(src, isNot(contains('buildThumbUrl')));
  });

  test('nothing reads the snapshot back to play or restore', () {
    // Hive is the only source of position. The widget's buttons name a book;
    // the app resumes it from its own records.
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      expect(src, isNot(contains('saga_widget')), reason: f.path);
    }
    final kotlin = File('packages/saga_native/android/src/main/kotlin/'
            'com/gaut3/saga/nativebridge/SagaWidget.kt')
        .readAsStringSync();
    expect(kotlin, isNot(contains('"position')));
  });
}
