import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saga/core/app_version.dart';

void main() {
  test('appVersionName matches pubspec.yaml', () {
    // A release built with a stale "-beta" here would show testers' tools
    // to everyone; a beta with a stale release name would hide them.
    final line = File('pubspec.yaml')
        .readAsLinesSync()
        .firstWhere((l) => l.startsWith('version:'));
    final name = line.substring('version:'.length).trim().split('+').first;
    expect(appVersionName, name);
  });
}
