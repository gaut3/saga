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

/// A parsed version: its numbers, and the pre-release part after a `-`
/// (`1.2.0-beta.2` → `[beta, 2]`), empty for a release.
typedef _Version = ({List<int> core, List<String> pre});

/// Version string → [_Version], or null when it isn't a version number.
/// Tolerant of a leading `v` and a `+build` suffix. Pre-release builds
/// (`-dev`, `-beta.N`) used to parse to null, so on a beta every check
/// failed and a tester was never told the final release was out.
_Version? _parseVersion(String s) {
  var v = s.trim();
  if (v.startsWith('v') || v.startsWith('V')) v = v.substring(1);
  final plus = v.indexOf('+');
  if (plus >= 0) v = v.substring(0, plus);
  var pre = const <String>[];
  final dash = v.indexOf('-');
  if (dash >= 0) {
    pre = v.substring(dash + 1).split('.');
    if (pre.any((p) => p.isEmpty)) return null;
    v = v.substring(0, dash);
  }
  if (v.isEmpty) return null;
  final nums = <int>[];
  for (final part in v.split('.')) {
    final n = int.tryParse(part);
    if (n == null || n < 0) return null;
    nums.add(n);
  }
  return (core: nums, pre: pre);
}

/// Semver order. Numbers first, missing ones counting as 0. With equal
/// numbers a release outranks any pre-release of it (`2.0.0` >
/// `2.0.0-beta.3`); pre-release parts compare as numbers when both are
/// (`beta.10` > `beta.9`), a number below a word, otherwise as text.
int _compareVersions(_Version a, _Version b) {
  final len = a.core.length > b.core.length ? a.core.length : b.core.length;
  for (var i = 0; i < len; i++) {
    final x = i < a.core.length ? a.core[i] : 0;
    final y = i < b.core.length ? b.core[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  if (a.pre.isEmpty || b.pre.isEmpty) {
    return (a.pre.isEmpty ? 1 : 0) - (b.pre.isEmpty ? 1 : 0);
  }
  for (var i = 0; i < a.pre.length && i < b.pre.length; i++) {
    final x = int.tryParse(a.pre[i]);
    final y = int.tryParse(b.pre[i]);
    final c = (x != null && y != null)
        ? x.compareTo(y)
        : (x != null)
            ? -1
            : (y != null)
                ? 1
                : a.pre[i].compareTo(b.pre[i]);
    if (c != 0) return c;
  }
  return a.pre.length.compareTo(b.pre.length);
}

/// True when [latestTag] is strictly newer than [currentVersion]; any
/// malformed input is false (never nag about an update we can't be sure
/// exists).
@visibleForTesting
bool isNewerVersion(String latestTag, String currentVersion) {
  final latest = _parseVersion(latestTag);
  final current = _parseVersion(currentVersion);
  if (latest == null || current == null) return false;
  return _compareVersions(latest, current) > 0;
}

/// The highest version tag in a GitHub `releases` listing, betas included;
/// drafts and tags that aren't versions are skipped. Null when none is left.
@visibleForTesting
String? newestReleaseTag(List<Object?> releases) {
  String? best;
  _Version? bestVersion;
  for (final r in releases) {
    if (r is! Map || r['draft'] == true) continue;
    final tag = r['tag_name'];
    if (tag is! String) continue;
    final v = _parseVersion(tag);
    if (v == null) continue;
    if (bestVersion == null || _compareVersions(v, bestVersion) > 0) {
      best = tag;
      bestVersion = v;
    }
  }
  return best;
}

/// One log line for a failed request. A [DioException]'s own text runs to
/// several lines, and the commonest failure, GitHub's hourly limit for
/// anonymous requests, deserves to be named.
String _describeFailure(Object e) {
  if (e is! DioException) return 'check failed: $e';
  final code = e.response?.statusCode;
  if (code == 403 || code == 429) {
    return 'GitHub refused the check (HTTP $code), most likely its hourly '
        'limit for anonymous requests';
  }
  return code != null
      ? 'check failed: HTTP $code'
      : 'check failed: ${e.type.name}';
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
    final current = _parseVersion(installed);
    if (current == null) {
      AppLog.log('update', 'installed version "$installed" is not a version '
          'number');
      return UpdateCheckResult(
          status: UpdateCheckStatus.failed, currentVersion: installed);
    }
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
    ));
    const headers = {'Accept': 'application/vnd.github+json'};
    final String? tag;
    if (current.pre.isEmpty) {
      // `releases/latest` deliberately skips drafts and pre-releases, so a
      // release install is never offered a beta.
      final resp = await dio.get<Map<String, dynamic>>(
        'https://api.github.com/repos/gaut3/saga/releases/latest',
        options: Options(headers: headers),
      );
      tag = resp.data?['tag_name'] as String?;
    } else {
      // A beta (or a -dev build) is offered newer betas as well as the
      // release that follows them, which `releases/latest` would hide. The
      // listing is newest first; 20 reaches well past the latest release.
      final resp = await dio.get<List<dynamic>>(
        'https://api.github.com/repos/gaut3/saga/releases',
        queryParameters: {'per_page': 20},
        options: Options(headers: headers),
      );
      tag = newestReleaseTag(resp.data ?? const []);
    }
    if (tag == null || tag.isEmpty) {
      AppLog.log('update', 'no release tag in the GitHub response');
      return UpdateCheckResult(
          status: UpdateCheckStatus.failed, currentVersion: installed);
    }
    final latest = _parseVersion(tag);
    // isNewerVersion reports an unparseable tag as "not newer", the safe
    // default, which would otherwise pass for a check that found nothing.
    if (latest == null) {
      AppLog.log('update', 'tag "$tag" is not a version number');
      return UpdateCheckResult(
          status: UpdateCheckStatus.failed,
          currentVersion: installed,
          latestTag: tag);
    }
    final newer = _compareVersions(latest, current) > 0;
    return UpdateCheckResult(
      status: newer ? UpdateCheckStatus.available : UpdateCheckStatus.current,
      currentVersion: installed,
      latestTag: tag,
    );
  } catch (e) {
    // Offline and rate-limited (60/hour per IP, unauthenticated) both land
    // here, and both are ordinary. Recorded so "it never says anything" can be
    // told apart from "it never runs".
    AppLog.log('update', _describeFailure(e));
    return UpdateCheckResult(
        status: UpdateCheckStatus.failed, currentVersion: installed);
  }
}

/// Cached per app session; MainShell kicks it off post-frame when enabled and
/// re-runs it on resume once a day has passed, and the Settings screen
/// re-reads/invalidates it from the toggle.
final updateCheckProvider =
    FutureProvider<UpdateCheckResult>((ref) => checkForUpdate());

/// Bumped by the update banner's tap; Settings scrolls its "Check for
/// updates" row into view on each bump.
final revealUpdateRowProvider = StateProvider<int>((_) => 0);
