import 'package:flutter_test/flutter_test.dart';
import 'package:saga/core/update/update_checker.dart';

void main() {
  test('equal versions are not newer', () {
    expect(isNewerVersion('v1.0.11', '1.0.11'), isFalse);
    expect(isNewerVersion('1.0.11', '1.0.11'), isFalse);
  });

  test('patch, minor, and major bumps are newer', () {
    expect(isNewerVersion('v1.0.12', '1.0.11'), isTrue);
    expect(isNewerVersion('v1.1.0', '1.0.11'), isTrue);
    expect(isNewerVersion('v2.0.0', '1.0.11'), isTrue);
  });

  test('older tags are not newer', () {
    expect(isNewerVersion('v1.0.10', '1.0.11'), isFalse);
    expect(isNewerVersion('v0.9.9', '1.0.11'), isFalse);
  });

  test('numeric comparison, not lexicographic', () {
    expect(isNewerVersion('v1.0.100', '1.0.11'), isTrue);
    expect(isNewerVersion('v1.10.0', '1.9.0'), isTrue);
  });

  test('build suffix and missing segments are tolerated', () {
    expect(isNewerVersion('v1.0.12+13', '1.0.11+12'), isTrue);
    expect(isNewerVersion('v1.1', '1.0.11'), isTrue);
    expect(isNewerVersion('v1', '1.0.0'), isFalse);
  });

  test('malformed input is never reported as an update', () {
    expect(isNewerVersion('latest', '1.0.11'), isFalse);
    expect(isNewerVersion('', '1.0.11'), isFalse);
    expect(isNewerVersion('v1.0.12', 'garbage'), isFalse);
    expect(isNewerVersion('v1.0.-2', '1.0.11'), isFalse);
  });

  // The author installs a locally-built APK before tagging the release, so the
  // installed version is normally equal to or ahead of what GitHub has. Both of
  // those must be quiet — and, just as importantly, must be *distinguishable*
  // from a check that failed, or the feature can never be confirmed to work by
  // the one person who runs it most.
  group('a build ahead of the latest release', () {
    test('is not offered an update when the tag catches up', () {
      expect(isNewerVersion('v1.0.18', '1.0.18'), isFalse);
    });

    test('is not offered an update while the tag is behind', () {
      // Built 1.0.18 locally; latest published release is still v1.0.17.
      expect(isNewerVersion('v1.0.17', '1.0.18'), isFalse);
    });

    test('is offered the next release once it is published', () {
      expect(isNewerVersion('v1.0.19', '1.0.18'), isTrue);
    });
  });

  group('outcomes are told apart', () {
    test('current and available are distinct statuses', () {
      const current = UpdateCheckResult(
          status: UpdateCheckStatus.current,
          currentVersion: '1.0.18',
          latestTag: 'v1.0.18');
      const available = UpdateCheckResult(
          status: UpdateCheckStatus.available,
          currentVersion: '1.0.18',
          latestTag: 'v1.0.19');
      expect(current.isNewer, isFalse);
      expect(available.isNewer, isTrue);
      expect(current.status, isNot(available.status));
    });

    test('a failure is not the same value as being up to date', () {
      // The bug this replaces: both were null, and the Settings tile rendered
      // them with the same words.
      const failed = UpdateCheckResult(status: UpdateCheckStatus.failed);
      const off = UpdateCheckResult(status: UpdateCheckStatus.off);
      expect(failed.isNewer, isFalse);
      expect(off.isNewer, isFalse);
      expect({
        UpdateCheckStatus.off,
        UpdateCheckStatus.current,
        UpdateCheckStatus.available,
        UpdateCheckStatus.failed,
      }.length, 4);
      expect(failed.status, isNot(off.status));
    });
  });
}
