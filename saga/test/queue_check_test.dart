// Sync design build step 2: a report queued offline is replayed only when
// it's newer than anything Plex has heard about the book since (rule 6),
// and Plex's times are read one way (rule 4).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saga/core/plex/models/plex_track.dart';
import 'package:saga/core/plex/plex_time.dart';
import 'package:saga/core/sync/sync_clock.dart';

void main() {
  group('Plex time fields', () {
    test('lastViewedAt is seconds, not milliseconds', () {
      // Chronicle's bug: seconds compared with its own milliseconds.
      expect(plexLastViewedAt(1763049600)!.toUtc(),
          DateTime.utc(2025, 11, 13, 16));
      expect(plexLastViewedAt(1763049600.0), plexLastViewedAt(1763049600));
    });

    test('absent or nonsense lastViewedAt is no information', () {
      for (final v in [null, 0, -5, 'yesterday', double.nan, double.infinity]) {
        expect(plexLastViewedAt(v), isNull, reason: '$v');
      }
    });

    test('viewOffset is ms; missing is no information, never 0', () {
      expect(plexViewOffsetMs(429100), 429100);
      expect(plexViewOffsetMs(0), 0);
      for (final v in [null, -1, '30000', double.nan]) {
        expect(plexViewOffsetMs(v), isNull, reason: '$v');
      }
    });

    test('PlexTrack reads both, and never caches them', () {
      final t = PlexTrack.fromJson({
        'ratingKey': '1',
        'key': '/library/metadata/1',
        'title': 'Part 1',
        'index': 1,
        'duration': 3600000,
        'viewOffset': 120000,
        'lastViewedAt': 1763049600,
      });
      expect(t.viewOffsetMs, 120000);
      expect(t.lastViewedAt, plexLastViewedAt(1763049600));
      final cached = PlexTrack.fromMap(t.toMap());
      expect(cached.viewOffsetMs, isNull);
      expect(cached.lastViewedAt, isNull);
    });

    test('a file Plex has no progress for', () {
      final t = PlexTrack.fromJson(
          {'ratingKey': '2', 'key': 'k', 'title': 'Part 2', 'index': 2});
      expect(t.viewOffsetMs, isNull);
      expect(t.lastViewedAt, isNull);
    });
  });

  group('newestViewedAt', () {
    test('the newest of the files, ignoring the ones with none', () {
      final a = DateTime.utc(2026, 11, 13, 10);
      final b = DateTime.utc(2026, 11, 13, 12);
      expect(newestViewedAt([a, null, b]), b);
      expect(newestViewedAt([null, null]), isNull);
      expect(newestViewedAt(const []), isNull);
    });
  });

  group('shouldReplayQueued', () {
    final server = DateTime.utc(2026, 11, 13, 12);
    bool replay(Duration queuedAfterServer) => shouldReplayQueued(
        queuedAt: server.add(queuedAfterServer), serverNewest: server);

    test('Plex has heard nothing of the book: replay', () {
      expect(
          shouldReplayQueued(queuedAt: server, serverNewest: null), isTrue);
    });

    test('queued well after Plex last heard of it: replay', () {
      expect(replay(const Duration(minutes: 40)), isTrue);
      expect(replay(const Duration(seconds: 61)), isTrue);
    });

    test('older than Plex\'s copy: drop', () {
      // Listened offline at 11:00, another device reported at 12:00, then
      // this phone reconnects: the blind replay this step exists to stop.
      expect(replay(-const Duration(hours: 1)), isFalse);
    });

    test('within the clock margin either way: drop', () {
      expect(replay(const Duration(seconds: 60)), isFalse);
      expect(replay(const Duration(seconds: 30)), isFalse);
      expect(replay(-const Duration(seconds: 30)), isFalse);
    });
  });

  group('shouldReplayQueued, two clocks', () {
    // skew = how far the server's clock is ahead of the phone's.
    final server = DateTime.utc(2026, 11, 13, 12);

    test('a fast phone does not make an old report look new', () {
      // Queued at a true 11:58, stamped 12:03 by a phone 5 min fast; the
      // other device reported at 12:00. Raw clocks say "3 min newer".
      final queuedAt = server.add(const Duration(minutes: 3));
      expect(shouldReplayQueued(queuedAt: queuedAt, serverNewest: server),
          isTrue,
          reason: 'the uncorrected comparison this fixes');
      expect(
          shouldReplayQueued(
              queuedAt: queuedAt,
              serverNewest: server,
              skew: -const Duration(minutes: 5)),
          isFalse);
    });

    test('a slow phone does not get a newer report dropped', () {
      // Queued at a true 12:10, stamped 12:00 by a phone 10 min slow.
      expect(
          shouldReplayQueued(
              queuedAt: server,
              serverNewest: server,
              skew: const Duration(minutes: 10)),
          isTrue);
    });

    test('the margin still applies after the correction', () {
      expect(
          shouldReplayQueued(
              queuedAt: server,
              serverNewest: server,
              skew: const Duration(seconds: 60)),
          isFalse);
    });
  });

  test('a queued report is replayed as stopped, never as playing', () {
    final src = File('lib/features/player/player_service.dart').readAsStringSync();
    final start = src.indexOf('Future<void> _flushTimelineQueue()');
    final body = src.substring(start, src.indexOf('\n  }\n', start));
    expect(body, contains("state: 'stopped'"));
    expect(body, isNot(contains('state: t.state')));
  });

  test('the replay loop asks before it sends', () {
    final src = File('lib/features/player/player_service.dart')
        .readAsLinesSync()
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
    final start = src.indexOf('Future<void> _flushTimelineQueue()');
    final body = src.substring(start, src.indexOf('\n  }\n', start));
    final fetch = body.indexOf('_api.fetchBookProgress(');
    final ask = body.indexOf('shouldReplayQueued(');
    final send = body.indexOf('_api.reportTimeline(');
    expect(fetch, isNot(-1), reason: 'reads the book from Plex, not a cache');
    expect(ask, greaterThan(fetch));
    expect(send, greaterThan(ask));
  });
}
