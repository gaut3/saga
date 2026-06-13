import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:saga/core/storage/playback_log_store.dart';

import 'helpers/hive_test_env.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await startHiveTestEnv();
    await PlaybackLogStore.init(testEncKey);
  });

  tearDown(() => stopHiveTestEnv(dir));

  AudioLogEvent event(DateTime ts, {String type = 'play'}) => AudioLogEvent(
        type: type,
        trackRatingKey: 'track-1',
        positionMs: 1000,
        timestamp: ts,
      );

  Map<String, dynamic> rawEvent(DateTime ts, {String type = 'play'}) =>
      event(ts, type: type).toMap();

  test('caps at 200 events per book, dropping the oldest first', () async {
    final base = DateTime(2026, 6, 1);
    for (var i = 0; i < 250; i++) {
      PlaybackLogStore.log(
          bookRatingKey: '42', event: event(base.add(Duration(minutes: i))));
    }
    // log() is fire-and-forget on the hot path; drain the write queue so the
    // queued puts (and their compactions) don't race the tearDown close.
    await Hive.box('playback_log').flush();
    final log = PlaybackLogStore.getLog('42');
    expect(log.length, 200);
    // The first 50 were evicted; the log starts at event #50.
    expect(log.first.timestamp, base.add(const Duration(minutes: 50)));
    expect(log.last.timestamp, base.add(const Duration(minutes: 249)));
  });

  test('importAll dedupes, sorts, and caps', () async {
    final base = DateTime(2026, 6, 1);
    PlaybackLogStore.log(bookRatingKey: '42', event: event(base));
    await Hive.box('playback_log').flush();
    await PlaybackLogStore.importAll({
      'log_42': [
        rawEvent(base), // duplicate of the local event
        rawEvent(base.subtract(const Duration(hours: 1))), // earlier
        rawEvent(base.add(const Duration(hours: 1))),
      ],
    });
    final log = PlaybackLogStore.getLog('42');
    expect(log.length, 3);
    expect(log.map((e) => e.timestamp).toList(), [
      base.subtract(const Duration(hours: 1)),
      base,
      base.add(const Duration(hours: 1)),
    ]);
  });

  group('pruneOldEvents', () {
    final now = DateTime(2026, 6, 12);

    test('removes events older than 12 months and reports the count',
        () async {
      await PlaybackLogStore.importAll({
        'log_mixed': [
          rawEvent(DateTime(2025, 1, 10)), // old
          rawEvent(DateTime(2025, 6, 11)), // one day past retention — old
          rawEvent(DateTime(2026, 6, 1)), // recent
        ],
        'log_recent': [rawEvent(DateTime(2026, 5, 1))],
      });
      final removed = await PlaybackLogStore.pruneOldEvents(now: now);
      expect(removed, 2);
      final mixed = PlaybackLogStore.getLog('mixed');
      expect(mixed.length, 1);
      expect(mixed.single.timestamp, DateTime(2026, 6, 1));
      expect(PlaybackLogStore.getLog('recent').length, 1);
    });

    test('events on the cutoff day itself are kept', () async {
      // Cutoff for now=2026-06-12 is midnight 2025-06-12.
      await PlaybackLogStore.importAll({
        'log_edge': [
          rawEvent(DateTime(2025, 6, 12)), // exactly at cutoff midnight
          rawEvent(DateTime(2025, 6, 11, 23, 59)), // one minute before
        ],
      });
      final removed = await PlaybackLogStore.pruneOldEvents(now: now);
      expect(removed, 1);
      expect(PlaybackLogStore.getLog('edge').single.timestamp,
          DateTime(2025, 6, 12));
    });

    test('deletes a book key entirely when all its events are old', () async {
      await PlaybackLogStore.importAll({
        'log_stale': [rawEvent(DateTime(2024, 1, 1))],
        'log_live': [rawEvent(DateTime(2026, 6, 1))],
      });
      await PlaybackLogStore.pruneOldEvents(now: now);
      expect(PlaybackLogStore.bookRatingKeys().toList(), ['live']);
      expect(PlaybackLogStore.getLog('stale'), isEmpty);
    });

    test('untouched books are not rewritten and nothing recent is removed',
        () async {
      await PlaybackLogStore.importAll({
        'log_a': [rawEvent(DateTime(2026, 6, 1))],
      });
      final removed = await PlaybackLogStore.pruneOldEvents(now: now);
      expect(removed, 0);
      expect(PlaybackLogStore.getLog('a').length, 1);
    });

    test('events with missing or invalid timestamps are dropped', () async {
      // Corrupt data can't be created through the store API — seed the
      // underlying box directly to exercise the validate-values guard.
      final box = Hive.box('playback_log');
      await box.put('log_bad', [
        rawEvent(DateTime(2026, 6, 1)),
        {'t': 'play', 'rk': 'track-1', 'p': 0}, // ts missing
        {'t': 'play', 'rk': 'track-1', 'p': 0, 'ts': 'corrupt'}, // not an int
      ]);
      final removed = await PlaybackLogStore.pruneOldEvents(now: now);
      expect(removed, 2);
      final log = PlaybackLogStore.getLog('bad');
      expect(log.length, 1);
      expect(log.single.timestamp, DateTime(2026, 6, 1));
    });
  });
}
