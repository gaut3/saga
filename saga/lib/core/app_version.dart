/// The version name from `pubspec.yaml`, pre-release part and all.
///
/// The platform can't be asked for it everywhere: iOS allows only digits in
/// a version, so Flutter strips `-dev` / `-beta.N` before Xcode sees it, and
/// an iOS dev build reports `1.3.0` like a release. What a build is (beta,
/// dev or release) is decided from this instead. Change it with pubspec's
/// `version:`; `test/app_version_test.dart` fails while they differ.
const appVersionName = '1.3.0-beta.3';
