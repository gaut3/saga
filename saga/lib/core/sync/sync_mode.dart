/// Cross-device position sync, shipped dark in 1.3.0 (sync design § Shipping
/// dark).
enum SyncMode {
  /// No extra network calls, no change. The default, and always the mode
  /// on a release build.
  off,

  /// Reads the server on an in-app open or play and logs what it would do
  /// ("would apply …"), moving nothing.
  shadow,

  /// Applies (build step 6).
  live,
}

/// The mode Saga runs in. A release build (no pre-release part in its
/// version) is always [SyncMode.off], whatever is stored: the stored value is
/// ignored there, not erased, so a tester moving from a beta to the release
/// simply stops syncing, and finds the setting again on the next beta.
///
/// Off too while developer options are hidden: the page is the only place
/// the mode shows, and a tester who hid it stayed in Live with no sign of it
/// anywhere. Hidden is ignored the same way, not erased: bringing the page
/// back brings the mode back.
SyncMode effectiveSyncMode({
  required bool prerelease,
  required bool developerOptions,
  required int storedIndex,
}) {
  if (!prerelease || !developerOptions) return SyncMode.off;
  if (storedIndex < 0 || storedIndex >= SyncMode.values.length) {
    return SyncMode.off;
  }
  return SyncMode.values[storedIndex];
}

/// How far the server's clock is ahead of the phone's (negative: behind),
/// from a response's `Date` header. The header has whole seconds, and the
/// server stamped it somewhere between sending the request and receiving
/// the answer, so it's compared with the middle of that window: good to
/// about a second, enough to see skew approach rule 4's 60 s margin.
Duration measureSkew({
  required DateTime sentAt,
  required DateTime receivedAt,
  required DateTime serverDate,
}) {
  final mid = sentAt.add(receivedAt.difference(sentAt) ~/ 2);
  return serverDate.difference(mid);
}
