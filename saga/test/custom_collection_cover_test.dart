import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saga/core/storage/custom_collection_store.dart';

import 'helpers/hive_test_env.dart';

/// A new collection used to sit on a folder icon until the user found the
/// "Set cover" action buried in its AppBar. It now adopts the first book's
/// artwork — but only the *first*, and never over a deliberate choice.
void main() {
  late Directory dir;

  setUp(() async {
    dir = await startHiveTestEnv();
    await CustomCollectionStore.init(testEncKey);
  });

  tearDown(() => stopHiveTestEnv(dir));

  group('CustomCollectionStore.addBook cover adoption', () {
    test('an empty collection adopts the first book\'s artwork', () async {
      final col = await CustomCollectionStore.create('Wheel of Time');
      expect(col.thumbPath, isNull);

      await CustomCollectionStore.addBook(col.id, 'b1',
          coverThumbPath: '/thumb/b1');

      expect(CustomCollectionStore.get(col.id)!.thumbPath, '/thumb/b1');
    });

    test('later books do not replace the adopted cover', () async {
      final col = await CustomCollectionStore.create('Wheel of Time');
      await CustomCollectionStore.addBook(col.id, 'b1',
          coverThumbPath: '/thumb/b1');
      await CustomCollectionStore.addBook(col.id, 'b2',
          coverThumbPath: '/thumb/b2');

      expect(CustomCollectionStore.get(col.id)!.thumbPath, '/thumb/b1');
    });

    test('never overwrites a cover the user picked', () async {
      final col = await CustomCollectionStore.create('Wheel of Time');
      await CustomCollectionStore.setCover(col.id, '/thumb/chosen');

      await CustomCollectionStore.addBook(col.id, 'b1',
          coverThumbPath: '/thumb/b1');

      expect(CustomCollectionStore.get(col.id)!.thumbPath, '/thumb/chosen');
    });

    test('respects a deliberate "None" — no re-adoption on the next add',
        () async {
      final col = await CustomCollectionStore.create('Wheel of Time');
      await CustomCollectionStore.addBook(col.id, 'b1',
          coverThumbPath: '/thumb/b1');
      // The user opens Set cover and chooses None.
      await CustomCollectionStore.setCover(col.id, null);

      await CustomCollectionStore.addBook(col.id, 'b2',
          coverThumbPath: '/thumb/b2');

      expect(CustomCollectionStore.get(col.id)!.thumbPath, isNull);
    });

    test('a book with no artwork leaves the collection cover-less', () async {
      final col = await CustomCollectionStore.create('Wheel of Time');
      await CustomCollectionStore.addBook(col.id, 'b1');

      expect(CustomCollectionStore.get(col.id)!.thumbPath, isNull);
      expect(CustomCollectionStore.get(col.id)!.bookRatingKeys, ['b1']);
    });

    test('adding a duplicate changes nothing', () async {
      final col = await CustomCollectionStore.create('Wheel of Time');
      await CustomCollectionStore.addBook(col.id, 'b1',
          coverThumbPath: '/thumb/b1');
      await CustomCollectionStore.addBook(col.id, 'b1',
          coverThumbPath: '/thumb/other');

      final stored = CustomCollectionStore.get(col.id)!;
      expect(stored.bookRatingKeys, ['b1']);
      expect(stored.thumbPath, '/thumb/b1');
    });

    test('removing every book does not clear the cover', () async {
      final col = await CustomCollectionStore.create('Wheel of Time');
      await CustomCollectionStore.addBook(col.id, 'b1',
          coverThumbPath: '/thumb/b1');
      await CustomCollectionStore.removeBook(col.id, 'b1');

      expect(CustomCollectionStore.get(col.id)!.thumbPath, '/thumb/b1');
    });

    test('rename and reorder leave the cover alone', () async {
      final col = await CustomCollectionStore.create('Wheel of Time');
      await CustomCollectionStore.addBook(col.id, 'b1',
          coverThumbPath: '/thumb/b1');
      await CustomCollectionStore.addBook(col.id, 'b2');

      await CustomCollectionStore.rename(col.id, 'WoT');
      await CustomCollectionStore.reorder(col.id, ['b2', 'b1']);

      final stored = CustomCollectionStore.get(col.id)!;
      expect(stored.name, 'WoT');
      expect(stored.bookRatingKeys, ['b2', 'b1']);
      expect(stored.thumbPath, '/thumb/b1');
    });
  });
}
