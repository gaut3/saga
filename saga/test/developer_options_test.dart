import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saga/core/storage/save_audit_store.dart';
import 'package:saga/core/update/update_checker.dart';

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

    SaveAuditEntry entry(int i, {bool reported = true}) => SaveAuditEntry(
          at: DateTime(2026, 11, 13, 10, 0, i),
          trigger: 'tick',
          bookKey: '23340',
          positionMs: i * 10000,
          reported: reported,
          heldUntilMs: reported ? null : 999999,
        );

    test('keeps only the last maxEntries saves, across a cold restart',
        () async {
      // A cache with no ceiling is a bug: this writes on every save.
      for (var i = 0; i < SaveAuditStore.maxEntries + 5; i++) {
        await SaveAuditStore.record(entry(i));
      }
      await coldRestartHive();
      await SaveAuditStore.init(testEncKey);
      final saves = SaveAuditStore.entries();
      expect(saves, hasLength(SaveAuditStore.maxEntries));
      // Newest first; the five oldest dropped.
      expect(saves.first.positionMs, (SaveAuditStore.maxEntries + 4) * 10000);
      expect(saves.last.positionMs, 5 * 10000);
    });

    test('a held save keeps its hold through a cold read', () async {
      await SaveAuditStore.record(entry(1, reported: false));
      await coldRestartHive();
      await SaveAuditStore.init(testEncKey);
      final s = SaveAuditStore.entries().single;
      expect(s.reported, isFalse);
      expect(s.heldUntilMs, 999999);
      expect(s.trigger, 'tick');
    });
  });
}
