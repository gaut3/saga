import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../diagnostics/app_log.dart';
import '../storage/settings_store.dart';

/// Opt-in update check (Settings › About). When the user has enabled it, a
/// single anonymous GET to the GitHub releases API compares the latest tag
/// to the installed version. Default off — this is the one explicitly
/// user-enabled exception to the no-background-network principle, documented
/// in PRIVACY_POLICY.md.
/// What the last check actually did.
///
/// This used to be a nullable result, where null meant *four* different things
/// — toggle off, network failed, GitHub said no, malformed tag — and the
/// Settings tile rendered every one of them as "View releases on GitHub". So a
/// check that had never once worked was indistinguishable from a check that
/// ran and found nothing, and there was no way to tell from inside the app
/// which you were looking at. Anyone who is normally *ahead* of the latest
/// release (anyone building locally before tagging) would never see this
/// feature succeed, and so could never confirm it works at all.
enum UpdateCheckStatus {
  /// The toggle is off. No request was made, and no claim is being made.
  off,

  /// GitHub answered: the installed version is current, or ahead of it.
  current,

  /// GitHub answered with a release newer than the installed version.
  available,

  /// The check ran and could not complete — offline, rate-limited, no release
  /// published yet, or a tag that isn't a version number.
  failed,
}

class UpdateCheckResult {
  final UpdateCheckStatus status;
  final String? currentVersion;
  final String? latestTag;

  const UpdateCheckResult({
    required this.status,
    this.currentVersion,
    this.latestTag,
  });

  bool get isNewer => status == UpdateCheckStatus.available;
}

/// Version string → numeric parts, or null when it isn't a version number.
/// Tolerant of a leading `v` and a `+build` suffix.
List<int>? _parseVersion(String s) {
  var v = s.trim();
  if (v.startsWith('v') || v.startsWith('V')) v = v.substring(1);
  final plus = v.indexOf('+');
  if (plus >= 0) v = v.substring(0, plus);
  if (v.isEmpty) return null;
  final nums = <int>[];
  for (final part in v.split('.')) {
    final n = int.tryParse(part);
    if (n == null || n < 0) return null;
    nums.add(n);
  }
  return nums;
}

/// True when [latestTag] is strictly newer than [currentVersion]; any
/// malformed input is false (never nag about an update we can't be sure
/// exists).
@visibleForTesting
bool isNewerVersion(String latestTag, String currentVersion) {
  final latest = _parseVersion(latestTag);
  final current = _parseVersion(currentVersion);
  if (latest == null || current == null) return false;
  final len = latest.length > current.length ? latest.length : current.length;
  for (var i = 0; i < len; i++) {
    final a = i < latest.length ? latest[i] : 0;
    final b = i < current.length ? current[i] : 0;
    if (a != b) return a > b;
  }
  return false;
}

/// Runs the check and always says what happened — never null.
///
/// Failures are logged. The old code deliberately kept quiet here to avoid
/// noise, but "quiet" and "broken" look identical from the outside, and this is
/// the one feature whose whole job is to tell you something you can't otherwise
/// find out. One line per launch at most, only on the unhappy path.
Future<UpdateCheckResult> checkForUpdate() async {
  if (!SettingsStore.updateCheckEnabled) {
    return const UpdateCheckResult(status: UpdateCheckStatus.off);
  }
  String? installed;
  try {
    final info = await PackageInfo.fromPlatform();
    installed = info.version;
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
    ));
    // `releases/latest` deliberately skips drafts and pre-releases, so a
    // release published as either is invisible here and reads as "no update".
    final resp = await dio.get<Map<String, dynamic>>(
      'https://api.github.com/repos/gaut3/saga/releases/latest',
      options: Options(headers: {'Accept': 'application/vnd.github+json'}),
    );
    final tag = resp.data?['tag_name'] as String?;
    if (tag == null || tag.isEmpty) {
      AppLog.log('update', 'no tag_name in the GitHub response');
      return UpdateCheckResult(
          status: UpdateCheckStatus.failed, currentVersion: installed);
    }
    final newer = isNewerVersion(tag, installed);
    // A side that parses to nothing is reported as "not newer" by
    // isNewerVersion, which is the safe default but would otherwise pass for a
    // successful check that found nothing.
    if (!newer &&
        (_parseVersion(tag) == null || _parseVersion(installed) == null)) {
      AppLog.log('update', 'tag "$tag" is not a version number');
      return UpdateCheckResult(
          status: UpdateCheckStatus.failed,
          currentVersion: installed,
          latestTag: tag);
    }
    return UpdateCheckResult(
      status: newer ? UpdateCheckStatus.available : UpdateCheckStatus.current,
      currentVersion: installed,
      latestTag: tag,
    );
  } catch (e) {
    // Offline and rate-limited (60/hour per IP, unauthenticated) both land
    // here, and both are ordinary. Recorded so "it never says anything" can be
    // told apart from "it never runs".
    AppLog.log('update', 'check failed: $e');
    return UpdateCheckResult(
        status: UpdateCheckStatus.failed, currentVersion: installed);
  }
}

/// Cached per app session; MainShell kicks it off post-frame when enabled,
/// and the Settings screen re-reads/invalidates it from the toggle.
final updateCheckProvider =
    FutureProvider<UpdateCheckResult>((ref) => checkForUpdate());
