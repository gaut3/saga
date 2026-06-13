import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../storage/settings_store.dart';

/// Opt-in update check (Settings › About). When the user has enabled it, a
/// single anonymous GET to the GitHub releases API compares the latest tag
/// to the installed version. Default off — this is the one explicitly
/// user-enabled exception to the no-background-network principle, documented
/// in PRIVACY_POLICY.md.
class UpdateCheckResult {
  final String currentVersion;
  final String latestTag;
  final bool isNewer;

  const UpdateCheckResult({
    required this.currentVersion,
    required this.latestTag,
    required this.isNewer,
  });
}

/// True when [latestTag] is strictly newer than [currentVersion]. Tolerant
/// of a leading `v` and a `+build` suffix; any malformed input is false
/// (never nag about an update we can't be sure exists).
@visibleForTesting
bool isNewerVersion(String latestTag, String currentVersion) {
  List<int>? parse(String s) {
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

  final latest = parse(latestTag);
  final current = parse(currentVersion);
  if (latest == null || current == null) return false;
  final len = latest.length > current.length ? latest.length : current.length;
  for (var i = 0; i < len; i++) {
    final a = i < latest.length ? latest[i] : 0;
    final b = i < current.length ? current[i] : 0;
    if (a != b) return a > b;
  }
  return false;
}

/// Null when the check is disabled or anything fails — failures are an
/// expected fallback on this path, so they are silent (no AppLog noise).
Future<UpdateCheckResult?> checkForUpdate() async {
  if (!SettingsStore.updateCheckEnabled) return null;
  try {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
    ));
    final resp = await dio.get<Map<String, dynamic>>(
      'https://api.github.com/repos/gaut3/saga/releases/latest',
      options: Options(headers: {'Accept': 'application/vnd.github+json'}),
    );
    final tag = resp.data?['tag_name'] as String?;
    if (tag == null || tag.isEmpty) return null;
    final info = await PackageInfo.fromPlatform();
    return UpdateCheckResult(
      currentVersion: info.version,
      latestTag: tag,
      isNewer: isNewerVersion(tag, info.version),
    );
  } catch (_) {
    return null;
  }
}

/// Cached per app session; MainShell kicks it off post-frame when enabled,
/// and the Settings screen re-reads/invalidates it from the toggle.
final updateCheckProvider =
    FutureProvider<UpdateCheckResult?>((ref) => checkForUpdate());
