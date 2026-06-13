import 'dart:io';

import 'package:hive_flutter/hive_flutter.dart';

/// Fixed 32-byte AES key for the encrypted test boxes. The stores'
/// `init(List<int>)` build their own [HiveAesCipher] from it.
const testEncKey = <int>[
  0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, //
  16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31,
];

/// Points Hive at a fresh temp directory. Call in `setUp`, then `init` the
/// stores under test with [testEncKey]. Pure-Dart `Hive.init` — no Flutter
/// binding or path_provider needed.
Future<Directory> startHiveTestEnv() async {
  final dir = await Directory.systemTemp.createTemp('saga_test_');
  Hive.init(dir.path);
  return dir;
}

/// Closes all boxes and removes the temp directory. Call in `tearDown`.
Future<void> stopHiveTestEnv(Directory dir) async {
  await Hive.close();
  try {
    await dir.delete(recursive: true);
  } catch (_) {
    // Windows can hold file locks briefly; a leaked temp dir is harmless.
  }
}
