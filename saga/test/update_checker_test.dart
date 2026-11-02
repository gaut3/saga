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

  // A beta build's version (1.2.0-beta.1) used to parse to nothing, so every
  // check on a beta failed and a tester was never told the release was out.
  group('pre-releases', () {
    test('the release outranks its own betas', () {
      expect(isNewerVersion('v1.2.0', '1.2.0-beta.3'), isTrue);
      expect(isNewerVersion('v1.2.0-beta.3', '1.2.0'), isFalse);
    });

    test('a later beta is newer, counted as a number', () {
      expect(isNewerVersion('v1.2.0-beta.2', '1.2.0-beta.1'), isTrue);
      expect(isNewerVersion('v1.2.0-beta.10', '1.2.0-beta.9'), isTrue);
      expect(isNewerVersion('v1.2.0-beta.1', '1.2.0-beta.1'), isFalse);
    });

    test('a beta of a later version beats an earlier release', () {
      expect(isNewerVersion('v1.3.0-beta.1', '1.2.0'), isTrue);
      expect(isNewerVersion('v1.1.3', '1.2.0-beta.1'), isFalse);
    });

    test('a -dev build ahead of the latest release is up to date', () {
      expect(isNewerVersion('v1.1.3', '1.2.0-dev'), isFalse);
      expect(isNewerVersion('v1.2.0', '1.2.0-dev'), isTrue);
    });

    test('an empty pre-release part is malformed', () {
      expect(isNewerVersion('v1.2.0-', '1.1.0'), isFalse);
      expect(isNewerVersion('v1.2.0-beta..1', '1.1.0'), isFalse);
    });
  });

  // What a beta install reads from GitHub's releases listing.
  group('newestReleaseTag', () {
    test('picks the highest version, wherever it sits in the list', () {
      expect(
          newestReleaseTag([
            {'tag_name': 'v1.2.0-beta.2'},
            {'tag_name': 'v1.2.0'},
            {'tag_name': 'v1.2.0-beta.1'},
            {'tag_name': 'v1.1.3'},
          ]),
          'v1.2.0');
    });

    test('a newer beta wins while the release is still to come', () {
      expect(
          newestReleaseTag([
            {'tag_name': 'v1.2.0-beta.2'},
            {'tag_name': 'v1.2.0-beta.1'},
            {'tag_name': 'v1.1.3'},
          ]),
          'v1.2.0-beta.2');
    });

    test('skips drafts, odd tags and odd entries', () {
      expect(
          newestReleaseTag([
            {'tag_name': 'v9.0.0', 'draft': true},
            {'tag_name': 'nightly'},
            {'tag_name': 7},
            'not a release',
            null,
            {'tag_name': 'v1.1.3'},
          ]),
          'v1.1.3');
    });

    test('nothing usable is null', () {
      expect(newestReleaseTag([]), isNull);
      expect(newestReleaseTag([{'tag_name': 'nightly'}]), isNull);
    });
  });
}
