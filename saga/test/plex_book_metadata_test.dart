import 'package:flutter_test/flutter_test.dart';
import 'package:saga/core/plex/models/plex_book.dart';

/// Plex's music schema has no narrator field; audiobook libraries put it in
/// **Style**. Everything that displays it has to cope with libraries that
/// aren't tagged that way, so absence is as important to pin as presence.
void main() {
  group('PlexBook narrator (Style) and genre', () {
    test('reads the narrator out of Style', () {
      final b = PlexBook.fromJson({
        'ratingKey': 1,
        'title': 'Overlord, Vol. 14',
        'Style': [
          {'tag': 'Chris Guerrero'}
        ],
      });
      expect(b.narrators, ['Chris Guerrero']);
      expect(b.narratorLabel, 'Chris Guerrero');
    });

    test('joins a full cast', () {
      final b = PlexBook.fromJson({
        'ratingKey': 1,
        'title': 'A book',
        'Style': [
          {'tag': 'Kate Reading'},
          {'tag': 'Michael Kramer'},
        ],
      });
      expect(b.narratorLabel, 'Kate Reading, Michael Kramer');
    });

    test('an untagged library yields no narrator, not an empty string', () {
      final b = PlexBook.fromJson({'ratingKey': 1, 'title': 'A book'});
      expect(b.narrators, isEmpty);
      // Callers hide the line on null; an empty string would render
      // "Narrated by ".
      expect(b.narratorLabel, isNull);
    });

    test('blank and malformed tags are dropped', () {
      final b = PlexBook.fromJson({
        'ratingKey': 1,
        'title': 'A book',
        'Style': [
          {'tag': ''},
          {'nottag': 'x'},
          'a bare string',
          {'tag': 'Real Narrator'},
        ],
      });
      expect(b.narrators, ['Real Narrator']);
    });

    test('genres parse from the same tag shape', () {
      final b = PlexBook.fromJson({
        'ratingKey': 1,
        'title': 'A book',
        'Genre': [
          {'tag': 'Fantasy'},
          {'tag': 'Adventure'},
        ],
      });
      expect(b.genres, ['Fantasy', 'Adventure']);
    });

    test('Style, Genre and Collection stay separate', () {
      final b = PlexBook.fromJson({
        'ratingKey': 1,
        'title': 'A book',
        'Style': [
          {'tag': 'The Narrator'}
        ],
        'Genre': [
          {'tag': 'Fantasy'}
        ],
        'Collection': [
          {'tag': 'Wheel of Time'}
        ],
      });
      expect(b.narrators, ['The Narrator']);
      expect(b.genres, ['Fantasy']);
      expect(b.collectionTags, ['Wheel of Time']);
    });

    test('existing fields still parse', () {
      final b = PlexBook.fromJson({
        'ratingKey': 42,
        'title': 'Overlord, Vol. 14',
        'parentTitle': 'Kugane Maruyama',
        'thumb': '/library/metadata/42/thumb/1',
        'year': 2021,
        'leafCount': 1,
        'summary': 'A summary.',
        'duration': 3723000,
        'studio': 'Yen Audio',
        'parentIndex': 14,
        'titleSort': 'Overlord 14',
      });
      expect(b.ratingKey, '42');
      expect(b.authorName, 'Kugane Maruyama');
      expect(b.year, 2021);
      expect(b.totalDurationMs, 3723000);
      expect(b.studio, 'Yen Audio');
      expect(b.seriesIndex, 14);
      expect(b.sortTitle, 'Overlord 14');
    });
  });
}
