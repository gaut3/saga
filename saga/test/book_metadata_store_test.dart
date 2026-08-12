import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saga/core/storage/book_download_store.dart';
import 'package:saga/core/storage/book_metadata_store.dart';
import 'package:saga/core/storage/bookmark_store.dart';
import 'package:saga/core/storage/server_scope.dart';
import 'package:saga/core/storage/settings_store.dart';

import 'helpers/hive_test_env.dart';

/// The per-book record is fetched once and cached forever, so the cache has to
/// survive a restart and has to keep working when the model gains fields — it
/// stores the raw Plex map for exactly that reason.
void main() {
  late Directory dir;

  setUp(() async {
    dir = await startHiveTestEnv();
    await BookMetadataStore.init(testEncKey);
  });

  tearDown(() => stopHiveTestEnv(dir));

  Map<String, dynamic> raw({List<String> style = const ['A Narrator']}) => {
        'ratingKey': 42,
        'title': 'A book',
        'parentTitle': 'An author',
        'Style': [for (final s in style) {'tag': s}],
        'Genre': [
          {'tag': 'Fantasy'}
        ],
      };

  test('a miss is null, not an exception', () {
    expect(BookMetadataStore.load('nope'), isNull);
  });

  test('saves and returns the parsed record', () async {
    await BookMetadataStore.save('42', raw());
    final b = BookMetadataStore.load('42')!;
    expect(b.title, 'A book');
    expect(b.narratorLabel, 'A Narrator');
    expect(b.genres, ['Fantasy']);
  });

  test('repeated loads reuse the decoded record', () async {
    await BookMetadataStore.save('42', raw());
    expect(identical(BookMetadataStore.load('42'), BookMetadataStore.load('42')),
        isTrue);
  });

  test('survives a restart, and re-parses from the stored raw map', () async {
    await BookMetadataStore.save('42', raw());
    // Re-init drops the in-memory decode cache; the box must still answer.
    await BookMetadataStore.init(testEncKey);
    expect(BookMetadataStore.load('42')?.narratorLabel, 'A Narrator');
  });

  test('a cold read from disk keeps the tag lists', () async {
    // The restart that matters: a new process, reading the box off disk, where
    // Hive hands back nested maps loosely typed. Tags parsed with a stricter
    // test than that come back empty, so the narrator and genre shown on the
    // first launch were simply gone on the second.
    await BookMetadataStore.save('42', raw());
    await coldRestartHive();
    await BookMetadataStore.init(testEncKey);

    final b = BookMetadataStore.load('42')!;
    expect(b.title, 'A book');
    expect(b.narratorLabel, 'A Narrator');
    expect(b.genres, ['Fantasy']);
  });

  test('a re-save replaces the cached record', () async {
    await BookMetadataStore.save('42', raw());
    await BookMetadataStore.save('42', raw(style: ['Someone Else']));
    expect(BookMetadataStore.load('42')?.narratorLabel, 'Someone Else');
  });

  test('a malformed entry reads as absent rather than throwing', () async {
    await BookMetadataStore.save('42', raw());
    await BookMetadataStore.init(testEncKey); // clear decode cache
    // Simulate a corrupt row by writing something PlexBook can't parse.
    await BookMetadataStore.save('43', {'no_rating_key': true});
    expect(() => BookMetadataStore.load('43'), returnsNormally);
  });

  test('the decode cache is bounded but stays correct', () async {
    for (var i = 0; i < 200; i++) {
      await BookMetadataStore.save('b$i', raw(style: ['N$i']));
    }
    expect(BookMetadataStore.load('b199')?.narratorLabel, 'N199');
    // Evicted from memory, still in the box.
    expect(BookMetadataStore.load('b0')?.narratorLabel, 'N0');
  });

  /// Sign-out prunes this box down to what sign-out promises to keep: books
  /// with a position or a download. Everything else is a title-and-author
  /// record of an account that just left.
  group('pruneOrphans', () {
    BookPosition pos() => BookPosition(
          trackRatingKey: 't1',
          positionMs: 1000,
          absolutePositionMs: 1000,
          savedAt: DateTime(2026, 8, 12),
        );

    setUp(() async {
      ServerScope.debugReset();
      await SettingsStore.init(testEncKey);
      await BookmarkStore.init(testEncKey);
      await BookDownloadStore.init(testEncKey);
    });

    test('keeps positioned and downloaded books, drops the rest', () async {
      await BookMetadataStore.save('started', raw());
      await BookMetadataStore.save('downloaded', raw());
      await BookMetadataStore.save('only-browsed', raw());
      await BookmarkStore.save('started', pos());
      BookDownloadStore.recordDownload('downloaded', 't1');

      final pruned = await BookMetadataStore.pruneOrphans();

      expect(pruned, 1);
      expect(BookMetadataStore.load('started'), isNotNull);
      expect(BookMetadataStore.load('downloaded'), isNotNull);
      expect(BookMetadataStore.load('only-browsed'), isNull,
          reason: 'the decoded cache must not resurrect a pruned record');
    });

    test('a secondary server\'s kept books survive too', () async {
      await ServerScope.configure('server-a'); // primary: bare keys
      await BookMetadataStore.save('11', raw());
      await BookmarkStore.save('11', pos());

      await ServerScope.configure('server-b'); // prefixed keys
      await BookMetadataStore.save('11', raw(style: ['B Narrator']));
      await BookmarkStore.save('11', pos());
      await BookMetadataStore.save('orphan', raw());

      // Signed out: the prune walks raw keys, so the scope in effect must not
      // decide whose records live.
      await ServerScope.configure(null);
      final pruned = await BookMetadataStore.pruneOrphans();

      expect(pruned, 1);
      expect(BookMetadataStore.load('11')?.narratorLabel, 'B Narrator',
          reason: 'signed out on server B, its record answers');
      expect(BookMetadataStore.load('orphan'), isNull);
      await ServerScope.configure('server-a');
      expect(BookMetadataStore.load('11')?.narratorLabel, 'A Narrator',
          reason: "the primary's copy of the same number is untouched");
    });
  });
}
