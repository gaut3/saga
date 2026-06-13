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
}
