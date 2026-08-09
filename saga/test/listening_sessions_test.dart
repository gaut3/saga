import 'package:flutter_test/flutter_test.dart';
import 'package:saga/core/stats/listening_sessions.dart';
import 'package:saga/core/storage/playback_log_store.dart';

AudioLogEvent _e(String type, int minute) => AudioLogEvent(
      type: type,
      trackRatingKey: 'track1',
      positionMs: 0,
      timestamp: DateTime(2026, 8, 9, 12, minute),
    );

/// The play→pause pairing used to exist as three hand-rolled copies (the
/// player's Sessions sheet and both of History's per-book panels) with three
/// different rules, and they had already drifted: the player's copy required
/// play and pause to be adjacent in the RAW log, so a skip or sleep-timer
/// event between them made the same session show a duration in History and
/// none in the player.
void main() {
  group('pairListeningSessions', () {
    test('pairs a plain play→pause', () {
      final sessions = pairListeningSessions([_e('play', 0), _e('pause', 42)]);
      expect(sessions, hasLength(1));
      expect(sessions.single.duration, const Duration(minutes: 42));
    });

    test('events between play and pause do not break the pair', () {
      // The drift that motivated the shared rule: skips and the sleep timer
      // log into the same list.
      final sessions = pairListeningSessions([
        _e('play', 0),
        _e('sleepTimer', 5),
        _e('skipNext', 10),
        _e('pause', 30),
      ]);
      expect(sessions, hasLength(1));
      expect(sessions.single.duration, const Duration(minutes: 30));
    });

    test('pairs by timestamp even when the input is out of order', () {
      final sessions = pairListeningSessions([_e('pause', 30), _e('play', 0)]);
      expect(sessions, hasLength(1));
      expect(sessions.single.duration, const Duration(minutes: 30));
    });

    test('a play with no pause is a session with unknown duration', () {
      final sessions = pairListeningSessions([_e('play', 0)]);
      expect(sessions, hasLength(1));
      expect(sessions.single.duration, isNull);
    });

    test('consecutive plays do not steal the next pause', () {
      // Double-logged play (crash between them): the earlier play must not be
      // credited with the later play's whole span.
      final sessions = pairListeningSessions([
        _e('play', 0),
        _e('play', 50),
        _e('pause', 60),
      ]);
      expect(sessions, hasLength(2));
      expect(sessions[0].duration, isNull);
      expect(sessions[1].duration, const Duration(minutes: 10));
    });

    test('an orphan pause pairs with nothing and credits no time', () {
      final sessions = pairListeningSessions([_e('pause', 5), _e('play', 10)]);
      expect(sessions, hasLength(1));
      expect(sessions.single.play.timestamp.minute, 10);
      expect(totalListened(sessions), Duration.zero);
    });

    test('totalListened sums only closed sessions', () {
      final sessions = pairListeningSessions([
        _e('play', 0),
        _e('pause', 10),
        _e('play', 20),
        _e('pause', 25),
        _e('play', 30), // still open
      ]);
      expect(totalListened(sessions), const Duration(minutes: 15));
    });
  });
}
