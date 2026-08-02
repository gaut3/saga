import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saga/core/storage/narrator_index_store.dart';

import 'helpers/hive_test_env.dart';

/// Plex can answer "which books does this narrator read"; sorting a book list
/// needs the opposite. The inversion is where that turns over, and the store is
/// what stops it costing a request per narrator every time.
void main() {
  group('invertNarratorIndex', () {
    test('maps each book to its narrator', () {
      final index = invertNarratorIndex([
        (narrator: 'Chris Guerrero', bookKeys: ['1', '2']),
        (narrator: 'Kate Reading', bookKeys: ['3']),
      ]);
      expect(index['1'], ['Chris Guerrero']);
      expect(index['2'], ['Chris Guerrero']);
      expect(index['3'], ['Kate Reading']);
    });

    test('a book with a full cast keeps every narrator, in tag order', () {
      final index = invertNarratorIndex([
        (narrator: 'Kate Reading', bookKeys: ['1']),
        (narrator: 'Michael Kramer', bookKeys: ['1']),
      ]);
      expect(index['1'], ['Kate Reading', 'Michael Kramer']);
    });

    test('a repeated tag does not duplicate the narrator', () {
      // Would otherwise render as "X, X" wherever narrators are joined.
      final index = invertNarratorIndex([
        (narrator: 'Chris Guerrero', bookKeys: ['1']),
        (narrator: 'Chris Guerrero', bookKeys: ['1']),
      ]);
      expect(index['1'], ['Chris Guerrero']);
    });

    test('a narrator with no books adds nothing', () {
      final index = invertNarratorIndex([
        (narrator: 'Nobody', bookKeys: <String>[]),
        (narrator: 'Someone', bookKeys: ['1']),
      ]);
      expect(index.containsKey('1'), isTrue);
      expect(index.length, 1);
    });

    test('an empty narrator name is skipped', () {
      final index = invertNarratorIndex([
        (narrator: '', bookKeys: ['1']),
      ]);
      expect(index, isEmpty);
    });

    test('an empty library yields an empty index', () {
      expect(invertNarratorIndex([]), isEmpty);
    });
  });

  group('NarratorIndexStore', () {
    late Directory dir;

    setUp(() async {
      dir = await startHiveTestEnv();
      await NarratorIndexStore.init(testEncKey);
    });

    tearDown(() => stopHiveTestEnv(dir));

    test('never built reads as null, not an empty index', () {
      // The distinction matters: null means "offer to build", empty would mean
      // "built, and this library has no narrators".
      expect(NarratorIndexStore.load('1'), isNull);
      expect(NarratorIndexStore.has('1'), isFalse);
      expect(NarratorIndexStore.builtAt('1'), isNull);
    });

    test('round-trips an index and stamps when it was built', () async {
      await NarratorIndexStore.save('1', {
        'b1': ['A Narrator'],
        'b2': ['Kate Reading', 'Michael Kramer'],
      });
      final loaded = NarratorIndexStore.load('1')!;
      expect(loaded['b1'], ['A Narrator']);
      expect(loaded['b2'], ['Kate Reading', 'Michael Kramer']);
      expect(NarratorIndexStore.builtAt('1'), isNotNull);
    });

    test('sections are independent', () async {
      await NarratorIndexStore.save('1', {
        'b1': ['Section One']
      });
      await NarratorIndexStore.save('2', {
        'b1': ['Section Two']
      });
      expect(NarratorIndexStore.load('1')!['b1'], ['Section One']);
      expect(NarratorIndexStore.load('2')!['b1'], ['Section Two']);
    });

    test('a rebuild replaces the previous index entirely', () async {
      await NarratorIndexStore.save('1', {
        'b1': ['Old'],
        'gone': ['Removed'],
      });
      await NarratorIndexStore.save('1', {
        'b1': ['New']
      });
      final loaded = NarratorIndexStore.load('1')!;
      expect(loaded['b1'], ['New']);
      expect(loaded.containsKey('gone'), isFalse);
    });

    test('clear returns it to never-built', () async {
      await NarratorIndexStore.save('1', {
        'b1': ['A']
      });
      await NarratorIndexStore.clear('1');
      expect(NarratorIndexStore.load('1'), isNull);
      expect(NarratorIndexStore.builtAt('1'), isNull);
    });

    test('survives a restart', () async {
      await NarratorIndexStore.save('1', {
        'b1': ['A Narrator']
      });
      await NarratorIndexStore.init(testEncKey);
      expect(NarratorIndexStore.load('1')!['b1'], ['A Narrator']);
    });
  });
}
