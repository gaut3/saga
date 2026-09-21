import 'package:flutter_test/flutter_test.dart';
import 'package:saga/core/cast/cast_service.dart';

// The serialized handoff crosses a process boundary (written to settings,
// read back after a relaunch mid-cast), so the parse is a trust boundary:
// a malformed or truncated value must come back null, never a half-filled
// handoff that files a position under the wrong key.
void main() {
  test('round-trips all fields', () {
    const h = CastHandoff(
      bookRatingKey: '12345',
      trackRatingKey: '67890',
      trackStartMs: 3600000,
      totalDurationMs: 7200000,
    );
    final back = CastHandoff.tryParse(h.serialize());
    expect(back, isNotNull);
    expect(back!.bookRatingKey, '12345');
    expect(back.trackRatingKey, '67890');
    expect(back.trackStartMs, 3600000);
    expect(back.totalDurationMs, 7200000);
  });

  test('round-trips a null total duration', () {
    const h = CastHandoff(
      bookRatingKey: '1',
      trackRatingKey: '2',
      trackStartMs: 0,
    );
    final back = CastHandoff.tryParse(h.serialize());
    expect(back, isNotNull);
    expect(back!.totalDurationMs, isNull);
  });

  test('rejects malformed values instead of half-parsing them', () {
    expect(CastHandoff.tryParse(''), isNull);
    expect(CastHandoff.tryParse('12345'), isNull);
    expect(CastHandoff.tryParse('12345|67890'), isNull);
    expect(CastHandoff.tryParse('|67890|0|'), isNull); // empty book key
    expect(CastHandoff.tryParse('12345||0|'), isNull); // empty track key
    expect(CastHandoff.tryParse('12345|67890|notanumber|'), isNull);
    expect(CastHandoff.tryParse('a|b|c|d|e'), isNull); // too many parts
  });
}
