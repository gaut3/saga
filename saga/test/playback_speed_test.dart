import 'package:flutter_test/flutter_test.dart';
import 'package:saga/core/playback_speed.dart';

void main() {
  test('stepping down from 1.0 lands on exact, printable speeds', () {
    var s = 1.0;
    final seen = <String>[];
    for (var i = 0; i < 5; i++) {
      s = stepSpeed(s, -1);
      seen.add(fmtSpeed(s));
    }
    expect(seen, ['0.95', '0.9', '0.85', '0.8', '0.75']);
    // Stepped there, it is the preset — the sheet checks the row by equality.
    expect(s, 0.75);
  });

  test('every step across the range prints at most two decimals', () {
    var s = kMinSpeed;
    while (s < kMaxSpeed) {
      expect(fmtSpeed(s).length, lessThanOrEqualTo(4), reason: '$s');
      s = stepSpeed(s, 1);
    }
    expect(s, kMaxSpeed);
  });

  test('stepping stops at the ends of the range', () {
    expect(stepSpeed(kMinSpeed, -1), kMinSpeed);
    expect(stepSpeed(kMaxSpeed, 1), kMaxSpeed);
  });

  test('a speed off the grid or out of range is snapped', () {
    expect(snapSpeed(0.8500000000000001), 0.85);
    expect(snapSpeed(0.1), kMinSpeed);
    expect(snapSpeed(9), kMaxSpeed);
    expect(snapSpeed(double.nan), 1.0);
    expect(snapSpeed(double.infinity), 1.0);
  });

  test('every preset is on the grid', () {
    for (final p in kSpeedPresets) {
      expect(snapSpeed(p), p);
    }
  });
}
