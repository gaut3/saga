import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saga/core/storage/bookmark_store.dart';
import 'package:saga/core/storage/completed_books_store.dart';
import 'package:saga/core/storage/custom_collection_store.dart';
import 'package:saga/core/storage/listen_days_store.dart';
import 'package:saga/core/storage/listening_history_store.dart';
import 'package:saga/core/storage/named_bookmark_store.dart';
import 'package:saga/core/storage/playback_log_store.dart';
import 'package:saga/core/storage/progress_backup.dart';

import 'helpers/hive_test_env.dart';

void main() {
  late Directory dir;

  Future<void> initAllStores() async {
    await BookmarkStore.init(testEncKey);
    await CompletedBooksStore.init(testEncKey);
    await NamedBookmarkStore.init(testEncKey);
    await CustomCollectionStore.init(testEncKey);
    await ListeningHistoryStore.init(testEncKey);
    await ListenDaysStore.init(testEncKey);
    await PlaybackLogStore.init(testEncKey);
  }

  Future<void> clearAllStores() async {
    await BookmarkStore.clearAll();
    await CompletedBooksStore.clearAll();
    await NamedBookmarkStore.clearAll();
    await CustomCollectionStore.delete('col-1');
    await ListeningHistoryStore.clearAll();
    await ListenDaysStore.clearAll();
    await PlaybackLogStore.clearAll();
  }

  setUp(() async {
    dir = await startHiveTestEnv();
    await initAllStores();
  });

  tearDown(() => stopHiveTestEnv(dir));

  final savedAt = DateTime(2026, 6, 10, 21, 30);

  Future<void> seedStores() async {
    await BookmarkStore.save(
      '101',
      BookPosition(
        trackRatingKey: '1001',
        positionMs: 123456,
        absolutePositionMs: 723456,
        totalDurationMs: 36000000,
        savedAt: savedAt,
      ),
    );
    await CompletedBooksStore.importAll({
      '202': [DateTime(2026, 5, 1, 20).millisecondsSinceEpoch],
    });
    await NamedBookmarkStore.save(NamedBookmark(
      id: 'bm-1',
      bookRatingKey: '101',
      trackRatingKey: '1001',
      positionMs: 555000,
      label: 'Great scene • 9:15',
      note: 'Den beste delen så langt',
      createdAt: DateTime(2026, 6, 1, 12),
    ));
    await CustomCollectionStore.restoreCollection(const CustomCollection(
      id: 'col-1',
      name: 'Wheel of Time',
      bookRatingKeys: ['101', '202'],
    ));
    await ListeningHistoryStore.importAll({
      't_2026-06-10': 1800000,
      'd_2026-06-10': [
        {'rk': '202', 't': 'Finished Book'},
      ],
    });
    await ListenDaysStore.importAll({
      '101': {
        's': '2026-06-01',
        'd': ['2026-06-01', '2026-06-10'],
      },
    });
    await PlaybackLogStore.importAll({
      'log_101': [
        AudioLogEvent(
          type: 'play',
          trackRatingKey: '1001',
          positionMs: 100000,
          timestamp: DateTime(2026, 6, 10, 21),
        ).toMap(),
        AudioLogEvent(
          type: 'pause',
          trackRatingKey: '1001',
          positionMs: 123456,
          timestamp: savedAt,
        ).toMap(),
      ],
    });
  }

  test('export -> JSON -> parse -> restore round-trips every store',
      () async {
    await seedStores();

    final map = ProgressBackup.buildBackupMap(serverMachineIdentifier: 'srv-1');
    final json = jsonEncode(map); // through real JSON, like the export file
    final data = ProgressBackup.parseBackupJson(json);
    expect(data, isNotNull);
    expect(data!.serverMachineIdentifier, 'srv-1');

    await clearAllStores();
    expect(BookmarkStore.load('101'), isNull);
    expect(CompletedBooksStore.isCompleted('202'), isFalse);

    await ProgressBackup.restore(data);

    final pos = BookmarkStore.load('101');
    expect(pos, isNotNull);
    expect(pos!.trackRatingKey, '1001');
    expect(pos.positionMs, 123456);
    expect(pos.absolutePositionMs, 723456);
    expect(pos.totalDurationMs, 36000000);
    expect(pos.savedAt, savedAt);

    expect(CompletedBooksStore.isCompleted('202'), isTrue);
    expect(CompletedBooksStore.completionCount('202'), 1);
    expect(CompletedBooksStore.completionDates('202').single,
        DateTime(2026, 5, 1, 20));

    final bookmarks = NamedBookmarkStore.getForBook('101');
    expect(bookmarks.single.label, 'Great scene • 9:15');
    expect(bookmarks.single.note, 'Den beste delen så langt');

    final col = CustomCollectionStore.get('col-1');
    expect(col, isNotNull);
    expect(col!.name, 'Wheel of Time');
    expect(col.bookRatingKeys, ['101', '202']);

    expect(ListeningHistoryStore.getMs(DateTime(2026, 6, 10)), 1800000);
    expect(
        ListeningHistoryStore.getCompleted(DateTime(2026, 6, 10))
            .single
            .ratingKey,
        '202');

    expect(ListenDaysStore.daysListened('101'), 2);
    expect(ListenDaysStore.startDate('101'), DateTime(2026, 6, 1));

    final log = PlaybackLogStore.getLog('101');
    expect(log.length, 2);
    expect(log.last.type, 'pause');
    expect(log.last.positionMs, 123456);
  });

  test('conflict detection flags backups older than local; skip keeps local',
      () async {
    await seedStores();
    final json =
        jsonEncode(ProgressBackup.buildBackupMap()); // backup at savedAt

    // The user listens on: local position is now newer than the backup.
    final newerAt = savedAt.add(const Duration(days: 1));
    await BookmarkStore.save(
      '101',
      BookPosition(
        trackRatingKey: '1001',
        positionMs: 999000,
        absolutePositionMs: 1599000,
        savedAt: newerAt,
      ),
    );

    final data = ProgressBackup.parseBackupJson(json)!;
    final conflicts = ProgressBackup.detectConflicts(data);
    expect(conflicts.length, 1);
    expect(conflicts.single.bookKey, '101');
    expect(conflicts.single.local.savedAt, newerAt);

    await ProgressBackup.restore(data, skipPositionKeys: {'101'});
    final pos = BookmarkStore.load('101')!;
    expect(pos.positionMs, 999000, reason: 'local newer position kept');
    expect(pos.savedAt, newerAt);
  });

  test('restoring without skip overwrites with the backup position', () async {
    await seedStores();
    final json = jsonEncode(ProgressBackup.buildBackupMap());
    await BookmarkStore.save(
      '101',
      BookPosition(
        trackRatingKey: '1001',
        positionMs: 999000,
        absolutePositionMs: 1599000,
        savedAt: savedAt.add(const Duration(days: 1)),
      ),
    );
    final data = ProgressBackup.parseBackupJson(json)!;
    await ProgressBackup.restore(data);
    expect(BookmarkStore.load('101')!.positionMs, 123456);
  });

  test('unknown backup versions are rejected', () {
    expect(ProgressBackup.parseBackupJson('{"version": 99}'), isNull);
    expect(ProgressBackup.parseBackupJson('{"version": 0}'), isNull);
    expect(ProgressBackup.parseBackupJson('{}'), isNull);
  });

  test('backup without server id parses with null identifier', () async {
    await seedStores();
    final json = jsonEncode(ProgressBackup.buildBackupMap());
    final data = ProgressBackup.parseBackupJson(json);
    expect(data, isNotNull);
    expect(data!.serverMachineIdentifier, isNull);
  });
}
