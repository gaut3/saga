// getRange/activeDays iterate calendar days; the DST cases here are only
// fully meaningful under Europe/Oslo (dev machine default, TZ pinned in CI).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saga/core/storage/listening_history_store.dart';

import 'helpers/hive_test_env.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await startHiveTestEnv();
    await ListeningHistoryStore.init(testEncKey);
  });

  tearDown(() => stopHiveTestEnv(dir));

  test('getRange returns every day exactly once across the DST boundary',
      () async {
    // Europe/Oslo springs forward 2026-03-29.
    await ListeningHistoryStore.importAll({
      't_2026-03-27': 1000,
      't_2026-03-29': 3000,
      't_2026-03-31': 5000,
    });
    final range = ListeningHistoryStore.getRange(
        DateTime(2026, 3, 27), DateTime(2026, 3, 31));
    expect(range.length, 5);
    expect(range.keys.toList(), [
      DateTime(2026, 3, 27),
      DateTime(2026, 3, 28),
      DateTime(2026, 3, 29),
      DateTime(2026, 3, 30),
      DateTime(2026, 3, 31),
    ]);
    expect(range[DateTime(2026, 3, 27)], 1000);
    expect(range[DateTime(2026, 3, 28)], 0);
    expect(range[DateTime(2026, 3, 29)], 3000);
    expect(range[DateTime(2026, 3, 31)], 5000);
  });

  test('getRange normalizes non-midnight bounds', () async {
    await ListeningHistoryStore.importAll({'t_2026-06-10': 1000});
    final range = ListeningHistoryStore.getRange(
        DateTime(2026, 6, 9, 14, 30), DateTime(2026, 6, 11, 8));
    expect(range.length, 3);
    expect(range[DateTime(2026, 6, 10)], 1000);
  });

  test('activeDays returns only days with activity, newest first', () async {
    await ListeningHistoryStore.importAll({
      't_2026-03-27': 1000,
      't_2026-03-30': 2000,
      'd_2026-03-29': [
        {'rk': '42', 't': 'A Book'},
      ],
    });
    final days = ListeningHistoryStore.activeDays(
        DateTime(2026, 3, 26), DateTime(2026, 3, 31));
    expect(days, [
      DateTime(2026, 3, 30),
      DateTime(2026, 3, 29), // completion-only day still counts
      DateTime(2026, 3, 27),
    ]);
  });

  test('importAll keeps the higher listening total per day', () async {
    await ListeningHistoryStore.importAll({'t_2026-06-01': 100});
    await ListeningHistoryStore.importAll({'t_2026-06-01': 50}); // older
    expect(ListeningHistoryStore.getMs(DateTime(2026, 6, 1)), 100);
    await ListeningHistoryStore.importAll({'t_2026-06-01': 200}); // newer
    expect(ListeningHistoryStore.getMs(DateTime(2026, 6, 1)), 200);
  });

  test('importAll merges completed-book lists without duplicates', () async {
    await ListeningHistoryStore.importAll({
      'd_2026-06-01': [
        {'rk': '1', 't': 'One'},
      ],
    });
    await ListeningHistoryStore.importAll({
      'd_2026-06-01': [
        {'rk': '1', 't': 'One'},
        {'rk': '2', 't': 'Two'},
      ],
    });
    final completed = ListeningHistoryStore.getCompleted(DateTime(2026, 6, 1));
    expect(completed.length, 2);
    expect(completed.map((c) => c.ratingKey).toSet(), {'1', '2'});
  });
}
