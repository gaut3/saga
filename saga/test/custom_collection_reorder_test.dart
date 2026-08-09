import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saga/core/storage/custom_collection_store.dart';

import 'helpers/hive_test_env.dart';

/// The reorder UI can only show books resolvable in the current library, so a
/// collection can hold keys the screen never saw: a book re-imported in Plex
/// under a new rating key, or one on another server. Writing the visible list
/// back verbatim silently deleted those on the first drag — reorder must merge
/// instead, keeping invisible keys in their original slots.
void main() {
  late Directory dir;

  setUp(() async {
    dir = await startHiveTestEnv();
    await CustomCollectionStore.init(testEncKey);
  });

  tearDown(() => stopHiveTestEnv(dir));

  group('CustomCollectionStore.reorder', () {
    test('applies the new order when every book was visible', () async {
      final col = await CustomCollectionStore.create('Series');
      for (final k in ['a', 'b', 'c']) {
        await CustomCollectionStore.addBook(col.id, k);
      }

      await CustomCollectionStore.reorder(col.id, ['c', 'a', 'b']);

      expect(CustomCollectionStore.get(col.id)!.bookRatingKeys,
          ['c', 'a', 'b']);
    });

    test('keeps books the reorder UI could not see, in their slots', () async {
      final col = await CustomCollectionStore.create('Series');
      // x and y are unresolvable in the current library (re-imported book,
      // other server) — the screen lists only a, b, c.
      for (final k in ['a', 'x', 'b', 'c', 'y']) {
        await CustomCollectionStore.addBook(col.id, k);
      }

      // The user drags c to the front of the visible list [a, b, c].
      await CustomCollectionStore.reorder(col.id, ['c', 'a', 'b']);

      // Visible slots (0, 2, 3) refilled in the new order; x and y untouched.
      expect(CustomCollectionStore.get(col.id)!.bookRatingKeys,
          ['c', 'x', 'a', 'b', 'y']);
    });

    test('a single visible book cannot wipe the rest', () async {
      final col = await CustomCollectionStore.create('Series');
      for (final k in ['a', 'x', 'y']) {
        await CustomCollectionStore.addBook(col.id, k);
      }

      await CustomCollectionStore.reorder(col.id, ['a']);

      expect(CustomCollectionStore.get(col.id)!.bookRatingKeys,
          ['a', 'x', 'y']);
    });
  });
}
