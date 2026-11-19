import 'package:flutter_test/flutter_test.dart';
import 'package:saga/features/player/player_provider.dart';

void main() {
  const five = Duration(minutes: 5);

  test('a step moves the time left by five minutes', () {
    const r = Duration(minutes: 23, seconds: 41);
    expect(adjustedSleepRemaining(r, five),
        const Duration(minutes: 28, seconds: 41));
    expect(adjustedSleepRemaining(r, -five),
        const Duration(minutes: 18, seconds: 41));
  });

  test('a step down never cancels or pauses at once', () {
    expect(adjustedSleepRemaining(const Duration(minutes: 3), -five),
        kMinSleepTimer);
    expect(adjustedSleepRemaining(const Duration(seconds: 10), -five),
        kMinSleepTimer);
  });

  test('a step up stops at the ceiling', () {
    expect(
        adjustedSleepRemaining(const Duration(minutes: 178), five),
        kMaxSleepTimer);
  });
}
