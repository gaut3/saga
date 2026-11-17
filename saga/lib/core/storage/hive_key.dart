import 'dart:convert';

/// The key every Hive box is encrypted with, or a refusal to make one up.
///
/// A missing key used to mean "first run": mint one and store it. But Hive
/// does not fail on a wrong key. It reads the first frame as corrupt and its
/// crash recovery truncates the file there, so opening the existing boxes
/// with a fresh key empties every one of them, positions included, without
/// an error. And the fresh key has by then replaced the stored one, so a read
/// that came back empty only this once (secure storage has done that) is
/// made permanent.
///
/// So a new key is minted only when there is nothing on disk to lose
/// ([boxesExist] false). With boxes present and no key, or a key that isn't
/// one, this throws, startup shows its error screen, and the boxes are left
/// as they are for the next launch.
Future<List<int>> loadHiveKey({
  required Future<String?> Function() read,
  required Future<void> Function(String value) write,
  required Future<bool> Function() boxesExist,
  required List<int> Function() generate,
}) async {
  final existing = await read();
  if (existing != null) {
    final key = base64Decode(existing);
    if (key.length != 32) {
      throw StateError(
          'stored encryption key is ${key.length} bytes, not 32: boxes left '
          'unopened');
    }
    return key;
  }
  if (await boxesExist()) {
    throw StateError(
        'encryption key missing while encrypted boxes exist: boxes left '
        'unopened rather than opened with a new key');
  }
  final key = generate();
  await write(base64Encode(key));
  return key;
}
