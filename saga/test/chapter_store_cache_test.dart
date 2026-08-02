import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saga/core/audio/m4b_chapter_reader.dart';
import 'package:saga/core/storage/chapter_store.dart';

import 'helpers/hive_test_env.dart';

/// [ChapterStore.load] is called on every position emission while a single-file
/// book plays, so it must not rebuild the list each time — and it must not go
/// stale, because chapters are usually written *after* playback has started.
void main() {
  late Directory dir;

  setUp(() async {
    dir = await startHiveTestEnv();
    await ChapterStore.init(testEncKey);
  });

  tearDown(() => stopHiveTestEnv(dir));

  const chapters = [
    M4bChapter(title: 'One', start: Duration.zero),
    M4bChapter(title: 'Two', start: Duration(minutes: 12)),
    M4bChapter(title: 'Three', start: Duration(minutes: 31)),
  ];

  test('round-trips chapters', () async {
    await ChapterStore.save('t1', chapters);
    final loaded = ChapterStore.load('t1')!;
    expect(loaded.length, 3);
    expect(loaded[1].title, 'Two');
    expect(loaded[2].start, const Duration(minutes: 31));
  });

  test('repeated loads reuse one decoded list', () async {
    await ChapterStore.save('t1', chapters);
    // Identity, not equality: rebuilding per call is the defect this guards.
    expect(identical(ChapterStore.load('t1'), ChapterStore.load('t1')), isTrue);
  });

  test('a save after a miss is visible immediately', () async {
    // The real sequence: playback starts before the chapters have been parsed,
    // so the first lookups miss. A cached miss must not outlive the write.
    expect(ChapterStore.load('t1'), isNull);
    await ChapterStore.save('t1', chapters);
    expect(ChapterStore.load('t1')?.length, 3);
  });

  test('a re-save replaces the cached list', () async {
    await ChapterStore.save('t1', chapters);
    await ChapterStore.save('t1', const [
      M4bChapter(title: 'Only', start: Duration.zero),
    ]);
    final loaded = ChapterStore.load('t1')!;
    expect(loaded.length, 1);
    expect(loaded.single.title, 'Only');
  });

  test('the returned list is unmodifiable — callers share the cache entry',
      () async {
    await ChapterStore.save('t1', chapters);
    expect(
      () => ChapterStore.load('t1')!.add(
          const M4bChapter(title: 'Nope', start: Duration.zero)),
      throwsUnsupportedError,
    );
  });

  test('a missing track stays null', () {
    expect(ChapterStore.load('nothing-here'), isNull);
    expect(ChapterStore.has('nothing-here'), isFalse);
  });

  test('the cache is bounded', () async {
    // Well past the cap; the point is that it stays correct, and that the
    // eviction path is actually exercised.
    for (var i = 0; i < 200; i++) {
      await ChapterStore.save('t$i', chapters);
    }
    // A recently written key is still right...
    expect(ChapterStore.load('t199')?.length, 3);
    // ...and an evicted one re-decodes from the box rather than vanishing.
    expect(ChapterStore.load('t0')?.length, 3);
  });
}
