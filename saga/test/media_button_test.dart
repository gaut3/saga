// "Headphone buttons skip" (GitHub #25): next/previous on headphones or a car
// skip by the skip lengths when it's on, and change chapter when it's off.
// Only the hardware buttons: the app's own buttons and Android Auto's screen
// call skipToNext/skipToPrevious directly and keep changing chapter.
//
// The handler needs a real AudioPlayer, so its routing is checked against the
// source, as report_gate_test does.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saga/core/storage/settings_store.dart';

import 'helpers/hive_test_env.dart';

void main() {
  group('the setting', () {
    late Directory dir;
    setUp(() async {
      dir = await startHiveTestEnv();
      await SettingsStore.init(testEncKey);
    });
    tearDown(() => stopHiveTestEnv(dir));

    test('is off by default: buttons change chapter', () {
      expect(SettingsStore.mediaButtonsSkip, isFalse);
    });

    test('survives a cold restart', () async {
      await SettingsStore.setMediaButtonsSkip(true);
      await coldRestartHive();
      await SettingsStore.init(testEncKey);
      expect(SettingsStore.mediaButtonsSkip, isTrue);
    });
  });

  group('the handler', () {
    final src = File('lib/features/player/player_service.dart')
        .readAsLinesSync()
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');

    String body(String signature) {
      final start = src.indexOf(signature);
      expect(start, isNot(-1), reason: '$signature not found');
      return src.substring(start, src.indexOf('\n  }\n', start));
    }

    String click() => body('Future<void> click([MediaButton button');

    test('next and previous skip only with the setting on', () {
      expect(click().contains('SettingsStore.mediaButtonsSkip'), isTrue);
      expect(click().contains('button != MediaButton.media'), isTrue,
          reason: 'play/pause is never a skip');
      expect(click().contains('fastForward()'), isTrue);
      expect(click().contains('rewind()'), isTrue);
    });

    test('otherwise the button does what it always did', () {
      expect(click().contains('super.click(button)'), isTrue);
    });

    test('the app\'s and Android Auto\'s next/previous are untouched', () {
      for (final sig in [
        'Future<void> skipToNext()',
        'Future<void> skipToPrevious()',
      ]) {
        expect(body(sig).contains('mediaButtonsSkip'), isFalse, reason: sig);
      }
    });
  });
}
