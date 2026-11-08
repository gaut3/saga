import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saga/core/storage/artwork_cache.dart';

/// The cover cache is the one thing Saga writes that has no natural end: a
/// file per book ever played, never overwritten, in app-private storage the
/// listener can only reclaim by clearing all of Saga's data — which would take
/// their positions and history with it. So the ceiling is pinned here.
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('saga_art_');
    ArtworkCache.debugSetDirectory(dir);
  });

  tearDown(() async {
    ArtworkCache.debugSetDirectory(null);
    try {
      await dir.delete(recursive: true);
    } catch (_) {
      // Windows can hold a lock briefly; a leaked temp dir is harmless.
    }
  });

  /// Writes [mb] megabytes under [name], stamped [ageMinutes] into the past so
  /// the eviction order is deterministic rather than dependent on how fast the
  /// test machine writes files.
  Future<File> writeCover(String name, int mb, {required int ageMinutes}) async {
    final f = File('${dir.path}/$name');
    await f.writeAsBytes(List<int>.filled(mb * 1024 * 1024, 0));
    await f.setLastModified(
        DateTime.now().subtract(Duration(minutes: ageMinutes)));
    return f;
  }

  Future<int> totalBytes() async {
    var total = 0;
    await for (final e in dir.list()) {
      if (e is File) total += await e.length();
    }
    return total;
  }

  test('a cache under the ceiling is left alone', () async {
    await writeCover('a.art', 1, ageMinutes: 100);
    await writeCover('b.art', 1, ageMinutes: 1);

    await ArtworkCache.prune();

    expect(File('${dir.path}/a.art').existsSync(), isTrue);
    expect(File('${dir.path}/b.art').existsSync(), isTrue);
  });

  test('an oversized cache is pruned back under the ceiling', () async {
    // 5 × 16 MB = 80 MB against a 64 MB ceiling.
    for (var i = 0; i < 5; i++) {
      await writeCover('cover$i.art', 16, ageMinutes: (5 - i) * 10);
    }
    expect(await totalBytes(), greaterThan(64 * 1024 * 1024));

    await ArtworkCache.prune();

    expect(await totalBytes(), lessThanOrEqualTo(64 * 1024 * 1024));
  });

  test('the oldest covers go first', () async {
    await writeCover('oldest.art', 30, ageMinutes: 300);
    await writeCover('middle.art', 30, ageMinutes: 200);
    await writeCover('newest.art', 30, ageMinutes: 10);

    await ArtworkCache.prune();

    // 90 MB down to 64 MB means exactly one file goes, and it is the one
    // written longest ago — evicting the newest would thrash the cover the
    // listener is most likely looking at.
    expect(File('${dir.path}/oldest.art').existsSync(), isFalse);
    expect(File('${dir.path}/middle.art').existsSync(), isTrue);
    expect(File('${dir.path}/newest.art').existsSync(), isTrue);
  });

  test('a download in flight is never pruned', () async {
    // A `.part` is a cover still being written; deleting it would fail that
    // download's rename. It's the oldest and largest here, so it would be the
    // first to go if prune counted it.
    await writeCover('pending.art.part', 40, ageMinutes: 500);
    await writeCover('a.art', 30, ageMinutes: 200);
    await writeCover('b.art', 30, ageMinutes: 10);

    await ArtworkCache.prune();

    expect(File('${dir.path}/pending.art.part').existsSync(), isTrue);
    expect(File('${dir.path}/a.art').existsSync(), isTrue);
    expect(File('${dir.path}/b.art').existsSync(), isTrue);
  });

  test('pruning an uninitialised cache is a no-op, not a crash', () async {
    ArtworkCache.debugSetDirectory(null);
    await expectLater(ArtworkCache.prune(), completes);
  });

  test('a missing directory is survived rather than thrown', () async {
    await dir.delete(recursive: true);
    await expectLater(ArtworkCache.prune(), completes);
  });

  group('shared URIs — what Android Auto opens', () {
    // `CoverProvider.kt` serves only names of one shape, under the authority
    // the manifest declares. Drift on either side is a car full of blank
    // tiles, visible nowhere but the car.
    const thumb = '/library/metadata/1/thumb/9';

    test('none for a cover that isn\'t cached', () {
      expect(ArtworkCache.getSharedUri(thumb), isNull);
      expect(ArtworkCache.getSharedUri(null), isNull);
    });

    test('a cached cover is named the way CoverProvider accepts', () async {
      await ArtworkCache.debugFileFor(thumb).writeAsBytes([0]);
      final uri = ArtworkCache.getSharedUri(thumb)!;
      expect(uri.scheme, 'content');
      expect(uri.host, ArtworkCache.sharedAuthority);
      expect(uri.pathSegments, hasLength(1));
      // CoverProvider.COVER_NAME.
      expect(uri.pathSegments.single, matches(RegExp(r'^[0-9a-f]{1,8}\.art$')));
    });

    test('Saga\'s own screens find the file behind either URI', () async {
      // The now-playing item carries the content URI; the player and the
      // mini player draw it from the file.
      final file = ArtworkCache.debugFileFor(thumb);
      await file.writeAsBytes([0]);
      expect(ArtworkCache.fileOf(ArtworkCache.getSharedUri(thumb)!)!.path,
          file.path);
      expect(ArtworkCache.fileOf(ArtworkCache.getLocalUri(thumb)!)!.path,
          file.path);
      expect(ArtworkCache.fileOf(Uri.parse('content://elsewhere/a.art')),
          isNull);
      expect(
          ArtworkCache.fileOf(Uri.parse(
              'content://${ArtworkCache.sharedAuthority}/a/b.art')),
          isNull);
    });

    test('the authority is the one the manifest gives CoverProvider', () {
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      final provider = RegExp(r'<provider[^>]*android:name="\.CoverProvider"[^>]*>')
          .stringMatch(manifest);
      expect(provider, isNotNull);
      expect(provider,
          contains('android:authorities="${ArtworkCache.sharedAuthority}"'));
      final kotlin = File(
              'android/app/src/main/kotlin/com/gaut3/saga/CoverProvider.kt')
          .readAsStringSync();
      expect(kotlin, contains(r'Regex("^[0-9a-f]{1,8}\\.art$")'));
    });
  });
}
