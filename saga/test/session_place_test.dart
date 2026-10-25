import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saga/core/audio/m4b_chapter_reader.dart';
import 'package:saga/core/plex/models/plex_track.dart';
import 'package:saga/core/storage/bookmark_store.dart';
import 'package:saga/core/storage/playback_log_store.dart';
import 'package:saga/features/player/session_place.dart';

AudioLogEvent _at(String track, int positionMs) => AudioLogEvent(
      type: 'pause',
      trackRatingKey: track,
      positionMs: positionMs,
      timestamp: DateTime(2026, 10, 25, 23, 40),
    );

PlexTrack _track(String key, int durationMs, String title, int index) =>
    PlexTrack(
      ratingKey: key,
      key: '/library/metadata/$key',
      title: title,
      durationMs: durationMs,
      index: index,
      partKey: '/library/parts/$key/file.mp3',
    );

List<M4bChapter>? _noChapters(String _) => null;

/// Sessions (player sheet, book detail, History) show where each session ran
/// and act on where it ended — so a wrong place here is a preview of the
/// wrong passage, or a resume to the wrong spot.
void main() {
  group('resolveEventPlace', () {
    final multi = [
      _track('a', 600000, 'Chapter 1', 0),
      _track('b', 900000, 'Chapter 2', 1),
      _track('c', 300000, 'Chapter 3', 2),
    ];

    test('a multi-file book places the event past the earlier files', () {
      final place = resolveEventPlace(_at('b', 120000),
          tracks: multi, saved: null, chaptersFor: _noChapters);
      expect(place?.absoluteMs, 600000 + 120000);
    });

    test("a multi-file book's chapter is the file's title", () {
      final place = resolveEventPlace(_at('c', 1000),
          tracks: multi, saved: null, chaptersFor: _noChapters);
      expect(place?.chapter, 'Chapter 3');
    });

    test('a single-file book takes the chapter starting at or before it', () {
      final chapters = [
        const M4bChapter(title: 'Prologue', start: Duration.zero),
        const M4bChapter(title: 'One', start: Duration(minutes: 10)),
        const M4bChapter(title: 'Two', start: Duration(minutes: 30)),
      ];
      List<M4bChapter>? chaptersFor(String key) => key == 'm4b' ? chapters : null;
      final single = [_track('m4b', 3600000, 'book.m4b', 0)];

      SessionPlace? at(Duration d) => resolveEventPlace(
          _at('m4b', d.inMilliseconds),
          tracks: single,
          saved: null,
          chaptersFor: chaptersFor);

      expect(at(const Duration(minutes: 29))?.chapter, 'One');
      // Exactly on a chapter start is that chapter, not the one before.
      expect(at(const Duration(minutes: 30))?.chapter, 'Two');
      expect(at(const Duration(minutes: 30))?.absoluteMs,
          const Duration(minutes: 30).inMilliseconds);
    });

    test("a single file's title is not mistaken for a chapter", () {
      final place = resolveEventPlace(_at('m4b', 5000),
          tracks: [_track('m4b', 3600000, 'book.m4b', 0)],
          saved: null,
          chaptersFor: _noChapters);
      expect(place?.chapter, isNull);
    });

    test('without a track list, the saved position places its own file', () {
      // The saved position knows one file's offset: absolute − relative.
      final saved = BookPosition(
        trackRatingKey: 'b',
        positionMs: 200000,
        absolutePositionMs: 800000,
        savedAt: DateTime(2026, 10, 25),
      );
      final place = resolveEventPlace(_at('b', 50000),
          tracks: null, saved: saved, chaptersFor: _noChapters);
      expect(place?.absoluteMs, 600000 + 50000);
    });

    test('an event nothing can place is null, not a guess', () {
      final saved = BookPosition(
        trackRatingKey: 'b',
        positionMs: 0,
        absolutePositionMs: 600000,
        savedAt: DateTime(2026, 10, 25),
      );
      expect(
          resolveEventPlace(_at('gone', 1000),
              tracks: multi, saved: saved, chaptersFor: _noChapters),
          isNull);
    });
  });

  group('previewWindow', () {
    Duration s(int seconds) => Duration(seconds: seconds);

    test('centres the clip on the position', () {
      final w = previewWindow(600000, 3600000);
      expect(w.start, s(585));
      expect(w.end, s(615));
    });

    test('near the start of a file it slides forward, not shorter', () {
      final w = previewWindow(5000, 3600000);
      expect(w.start, Duration.zero);
      expect(w.end, s(30));
    });

    test('near the end of a file it slides back, not shorter', () {
      final w = previewWindow(3595000, 3600000);
      expect(w.start, s(3570));
      expect(w.end, s(3600));
    });

    test('a file shorter than the clip plays whole', () {
      final w = previewWindow(4000, 12000);
      expect(w.start, Duration.zero);
      expect(w.end, s(12));
    });

    test('an unknown duration leaves the end where the clip ends', () {
      final w = previewWindow(600000, 0);
      expect(w.start, s(585));
      expect(w.end, s(615));
    });
  });

  group('the preview never touches the main player', () {
    // A preview exists to let the listener try a spot *without* moving their
    // place. Everything that records listening is wired to the main player;
    // this pins that the preview file never reaches for any of it. Asserted
    // against the source because none of it is observable in a unit test —
    // there's no platform player here.
    String code(String path) => File(path)
        .readAsLinesSync()
        .where((l) => !l.trimLeft().startsWith('//') &&
            !l.trimLeft().startsWith('///'))
        .join('\n');

    final src = code('lib/features/player/session_preview.dart');

    for (final forbidden in [
      'BookmarkStore', // the saved position
      'PlaybackLogStore', // sessions
      '_logEvent',
      'ListeningHistoryStore', // daily listening time
      'ListenDaysStore',
      'mediaItem', // the platform media session
      'playbackState.add',
      'TimelineQueueStore', // Plex progress reports
      'seekAbsolute',
    ]) {
      test('no $forbidden', () {
        expect(src, isNot(contains(forbidden)));
      });
    }

    test('the preview player never runs the header proxy', () {
      // Same reason as the main player (CLAUDE.md § Security): the proxy is
      // a cleartext loopback server serving the user's audiobooks.
      expect(src, contains('useProxyForRequestHeaders: false'));
    });

    test('the shared audio source authenticates by header', () {
      final audio = code('lib/features/player/track_audio_source.dart');
      expect(audio, contains('headers: PlexClient.instance.authHeaders'));
      expect(audio, isNot(contains('X-Plex-Token')));
      expect(audio, isNot(contains('buildCastMedia')));
    });
  });
}
