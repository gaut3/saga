import 'package:flutter_test/flutter_test.dart';
import 'package:saga/core/plex/models/plex_track.dart';

void main() {
  group('PlexTrack toMap/fromMap', () {
    test('round-trips every field', () {
      const track = PlexTrack(
        ratingKey: '4711',
        key: '/library/metadata/4711',
        title: 'Kapittel 1 — Æresgjesten',
        bookTitle: 'En bok',
        authorName: 'Forfatter Navn',
        thumbPath: '/library/metadata/4700/thumb/123',
        durationMs: 3723000,
        index: 1,
        partKey: '/library/parts/999/file.m4b',
        partFile: '/data/books/file.m4b',
      );

      final restored = PlexTrack.fromMap(track.toMap());

      expect(restored.ratingKey, track.ratingKey);
      expect(restored.key, track.key);
      expect(restored.title, track.title);
      expect(restored.bookTitle, track.bookTitle);
      expect(restored.authorName, track.authorName);
      expect(restored.thumbPath, track.thumbPath);
      expect(restored.durationMs, track.durationMs);
      expect(restored.index, track.index);
      expect(restored.partKey, track.partKey);
      expect(restored.partFile, track.partFile);
    });

    test('round-trips null optionals', () {
      const track = PlexTrack(
        ratingKey: '1',
        key: '/library/metadata/1',
        title: 't',
        durationMs: 0,
        index: 0,
        partKey: '/parts/1',
      );

      final restored = PlexTrack.fromMap(track.toMap());

      expect(restored.bookTitle, isNull);
      expect(restored.authorName, isNull);
      expect(restored.thumbPath, isNull);
      expect(restored.partFile, isNull);
    });

    test('missing keys in a stored map fall back instead of throwing', () {
      final restored = PlexTrack.fromMap(const {});
      expect(restored.ratingKey, '');
      expect(restored.durationMs, 0);
      expect(restored.index, 0);
    });
  });
}
