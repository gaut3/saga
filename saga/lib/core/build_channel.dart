import 'package:package_info_plus/package_info_plus.dart';

import 'storage/settings_store.dart';
import 'update/update_checker.dart' show isPrereleaseVersion;

/// Which kind of build this is. A beta or dev build has a pre-release part in
/// its version (`1.3.0-beta.2`, `1.3.0-dev`); a release has none — the test
/// the update checker uses to decide whether to offer betas.
///
/// Developer options exist only on a pre-release build, and so does the sync
/// mode (sync design § Shipping dark): a release reads neither setting,
/// whatever is stored, and erases nothing.
class BuildChannel {
  static bool _prerelease = false;
  static String _version = '';

  /// False until [init] has run, and when the version can't be read: a build
  /// that can't tell counts as a release.
  static bool get isPrerelease => _prerelease;

  /// `1.3.0-dev+32`, or empty when it couldn't be read.
  static String get version => _version;

  /// Developer options are on: a beta or dev build, unlocked in About.
  static bool get developerOptions =>
      _prerelease && SettingsStore.developerOptions;

  static Future<void> init() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _version = '${info.version}+${info.buildNumber}';
      _prerelease = isPrereleaseVersion(info.version);
    } catch (_) {
      // Stays a release: nothing gated on the channel opens.
    }
  }
}
