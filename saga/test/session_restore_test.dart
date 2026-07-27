import 'package:flutter_test/flutter_test.dart';
import 'package:saga/core/storage/bookmark_store.dart';
import 'package:saga/features/player/session_restore.dart';

BookPosition _pos(DateTime savedAt) => BookPosition(
      trackRatingKey: 't',
      positionMs: 1000,
      absolutePositionMs: 1000,
      savedAt: savedAt,
    );

void main() {
  group('mostRecentBookRatingKey', () {
    test('empty map returns null', () {
      expect(mostRecentBookRatingKey(const {}), isNull);
    });

    test('single entry wins', () {
      final positions = {'a': _pos(DateTime(2026, 7, 1))};
      expect(mostRecentBookRatingKey(positions), 'a');
    });

    test('picks the most recently saved position', () {
      final positions = {
        'older': _pos(DateTime(2026, 6, 1)),
        'newest': _pos(DateTime(2026, 7, 18, 21, 30)),
        'middle': _pos(DateTime(2026, 7, 1)),
      };
      expect(mostRecentBookRatingKey(positions), 'newest');
    });

    test('newest wins regardless of map insertion order', () {
      final positions = {
        'newest': _pos(DateTime(2026, 7, 18)),
        'older': _pos(DateTime(2026, 6, 1)),
      };
      expect(mostRecentBookRatingKey(positions), 'newest');
    });
  });
}
