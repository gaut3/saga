import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saga/core/storage/book_metadata_store.dart';

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
    expect(BookMetadataStore.has('nope'), isFalse);
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
}
