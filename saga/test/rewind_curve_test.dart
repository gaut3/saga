import 'package:flutter_test/flutter_test.dart';
import 'package:saga/features/player/resume_rewind.dart';

void main() {
  test('no rewind at or under 5 seconds away', () {
    expect(resumeRewindMs(0, enabled: true), 0);
    expect(resumeRewindMs(3, enabled: true), 0);
    expect(resumeRewindMs(5, enabled: true), 0);
  });

  test('50 ms per second away above the threshold', () {
    expect(resumeRewindMs(6, enabled: true), 300);
    expect(resumeRewindMs(100, enabled: true), 5000); // 5 s per 100 s
    expect(resumeRewindMs(600, enabled: true), 30000);
  });

  test('caps at 60 seconds', () {
    expect(resumeRewindMs(1200, enabled: true), 60000);
    expect(resumeRewindMs(1201, enabled: true), 60000);
    expect(resumeRewindMs(1000000, enabled: true), 60000);
  });

  test('disabled always returns 0', () {
    expect(resumeRewindMs(0, enabled: false), 0);
    expect(resumeRewindMs(100, enabled: false), 0);
    expect(resumeRewindMs(1000000, enabled: false), 0);
  });
}
