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

  test('pruning an uninitialised cache is a no-op, not a crash', () async {
    ArtworkCache.debugSetDirectory(null);
    await expectLater(ArtworkCache.prune(), completes);
  });

  test('a missing directory is survived rather than thrown', () async {
    await dir.delete(recursive: true);
    await expectLater(ArtworkCache.prune(), completes);
  });
}
