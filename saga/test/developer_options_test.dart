import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saga/core/storage/save_audit_store.dart';
import 'package:saga/core/update/update_checker.dart';
import 'package:saga/features/player/report_gate.dart';

import 'helpers/hive_test_env.dart';

void main() {
  group('isPrereleaseVersion', () {
    // Developer options, and later the sync mode, exist only on beta and dev
    // builds. A release that read as a pre-release would show testers' tools
    // to everyone (sync design § Shipping dark).
    test('a release version is never a pre-release', () {
      for (final v in ['1.2.0', '1.2.0+31', 'v1.2.0', '2.0.0+2040']) {
        expect(isPrereleaseVersion(v), isFalse, reason: v);
      }
    });

    test('betas and dev builds are', () {
      for (final v in ['1.3.0-dev', '1.3.0-dev+32', '1.2.0-beta.7+30']) {
        expect(isPrereleaseVersion(v), isTrue, reason: v);
      }
    });

    test('a version that does not parse counts as a release', () {
      for (final v in ['', 'dev', '1.x.0-beta', '1.2.0-']) {
        expect(isPrereleaseVersion(v), isFalse, reason: v);
      }
    });
  });

  group('SaveAuditStore', () {
    late Directory dir;

    setUp(() async {
      dir = await startHiveTestEnv();
      await SaveAuditStore.init(testEncKey);
    });

    tearDown(() => stopHiveTestEnv(dir));

    Future<int?> save(int s,
            {String trigger = 'tick',
            ReportStatus report = ReportStatus.sent}) =>
        SaveAuditStore.record(
          at: DateTime(2026, 11, 13, 17, 0, s),
          trigger: trigger,
          bookKey: '23340',
          positionMs: s * 1000,
          report: report,
          heldUntilMs: report == ReportStatus.held ? 999999 : null,
        );

    Future<List<SaveAuditEntry>> coldEntries() async {
      await coldRestartHive();
      await SaveAuditStore.init(testEncKey);
      return SaveAuditStore.entries();
    }

    test('a run of ticks folds into one row', () async {
      for (var s = 0; s < 50; s += 10) {
        await save(s);
      }
      final row = (await coldEntries()).single;
      expect(row.count, 5);
      expect(row.fromPositionMs, 0);
      expect(row.positionMs, 40000);
      expect(row.id, DateTime(2026, 11, 13, 17).millisecondsSinceEpoch);
    });

    test('anything else breaks a run, and so does a change of status',
        () async {
      await save(0, report: ReportStatus.held);
      await save(10, report: ReportStatus.held);
      await save(20); // the hold passed: a new run
      await save(30);
      await save(35, trigger: 'pause');
      await save(40, trigger: 'hidden', report: ReportStatus.repeat);
      await save(50); // ticks again after the pause: not the old run
      final rows = await coldEntries();
      expect([for (final r in rows) '${r.trigger}×${r.count}'],
          ['tick×1', 'hidden×1', 'pause×1', 'tick×2', 'tick×2']);
      expect(rows.last.report, ReportStatus.held);
      expect(rows.last.heldUntilMs, 999999);
    });

    test('keeps only the last maxEntries rows', () async {
      // A cache with no ceiling is a bug: this writes on every save.
      for (var i = 0; i < SaveAuditStore.maxEntries + 5; i++) {
        await save(i, trigger: 'pause');
      }
      final rows = await coldEntries();
      expect(rows, hasLength(SaveAuditStore.maxEntries));
      expect(rows.first.positionMs, (SaveAuditStore.maxEntries + 4) * 1000);
      expect(rows.last.positionMs, 5 * 1000);
    });

    test('outcomes land on their row, run or not', () async {
      final a = await save(0);
      final b = await save(10);
      expect(b, a, reason: 'a folded tick shares its run\'s id');
      await SaveAuditStore.recordOutcome(a!, 'ok');
      await SaveAuditStore.recordOutcome(a, 'queued');
      final p = await save(15, trigger: 'pause');
      await SaveAuditStore.recordOutcome(p!, 'http 404');
      await SaveAuditStore.recordOutcome(12345, 'ok'); // scrolled out: ignored
      final rows = await coldEntries();
      expect(rows.first.outcomes, {'http 404': 1});
      expect(rows.last.outcomes, {'ok': 1, 'queued': 1});
    });

    test('two saves in one millisecond get their own rows', () async {
      final a = await save(0, trigger: 'pause');
      final b = await save(0, trigger: 'hidden');
      expect(b, a! + 1);
    });
  });

  group('isRepeatReport', () {
    const base = (
      bookKey: '23340',
      trackRatingKey: 't1',
      positionMs: 429100,
      state: 'paused',
    );

    test('the same place and state again is a repeat', () {
      expect(isRepeatReport(base, base), isTrue);
      expect(
          isRepeatReport(base, (
            bookKey: '23340',
            trackRatingKey: 't1',
            positionMs: 429900,
            state: 'paused',
          )),
          isTrue);
    });

    test('a new place, file, book or state is not', () {
      expect(isRepeatReport(null, base), isFalse);
      for (final next in [
        (bookKey: '23340', trackRatingKey: 't1', positionMs: 431000, state: 'paused'),
        (bookKey: '23340', trackRatingKey: 't2', positionMs: 429100, state: 'paused'),
        (bookKey: '99', trackRatingKey: 't1', positionMs: 429100, state: 'paused'),
        // A stop after a pause still goes: it ends the play in Plex.
        (bookKey: '23340', trackRatingKey: 't1', positionMs: 429100, state: 'stopped'),
      ]) {
        expect(isRepeatReport(base, next), isFalse, reason: '$next');
      }
    });
  });
}
