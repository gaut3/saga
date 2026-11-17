import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:saga/core/storage/hive_key.dart';

void main() {
  final fresh = List<int>.generate(32, (i) => i);

  test('first run: no key, no boxes, mints and stores one', () async {
    String? stored;
    final key = await loadHiveKey(
      read: () async => null,
      write: (v) async => stored = v,
      boxesExist: () async => false,
      generate: () => fresh,
    );
    expect(key, fresh);
    expect(base64Decode(stored!), fresh);
  });

  test('a stored key is returned and nothing is written', () async {
    final key = await loadHiveKey(
      read: () async => base64Encode(fresh),
      write: (_) async => fail('must not overwrite a stored key'),
      boxesExist: () async => true,
      generate: () => fail('must not generate'),
    );
    expect(key, fresh);
  });

  test('no key but boxes on disk: refuses, and leaves the key slot alone',
      () async {
    await expectLater(
      loadHiveKey(
        read: () async => null,
        write: (_) async => fail('a new key would empty every box'),
        boxesExist: () async => true,
        generate: () => fail('must not generate'),
      ),
      throwsStateError,
    );
  });

  test('a stored value that is not a 32-byte key is refused', () async {
    await expectLater(
      loadHiveKey(
        read: () async => base64Encode([1, 2, 3]),
        write: (_) async => fail('must not write'),
        boxesExist: () async => true,
        generate: () => fail('must not generate'),
      ),
      throwsStateError,
    );
  });
}
