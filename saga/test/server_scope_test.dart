import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saga/core/plex/models/plex_track.dart';
import 'package:saga/core/storage/bookmark_store.dart';
import 'package:saga/core/storage/completed_books_store.dart';
import 'package:saga/core/storage/named_bookmark_store.dart';
import 'package:saga/core/storage/narrator_index_store.dart';
import 'package:saga/core/storage/playback_log_store.dart';
import 'package:saga/core/storage/server_scope.dart';
import 'package:saga/core/storage/settings_store.dart';
import 'package:saga/core/storage/timeline_queue_store.dart';
import 'package:saga/core/storage/track_cache_store.dart';
import 'package:saga/core/storage/want_to_read_store.dart';

import 'helpers/hive_test_env.dart';

/// A Plex `ratingKey` is unique only *within one server*. Every per-book store
/// keys by it, so two servers both having a book `12345` meant the second
/// silently inherited the first's position, completion, downloads and cached
/// tracks. Plex lists servers shared with you next to your own, so having a
/// second one is ordinary.
///
/// The two things these tests exist to hold down:
///   1. For anyone with one server — which is nearly everyone, including every
///      existing install — the keys are **byte-identical to before**, so the
///      change needs no migration and cannot strand a saved position.
///   2. For anyone with two, the servers cannot see or overwrite each other.
void main() {
  late Directory dir;

  Future<void> initStores() async {
    // Every store shares one box directory; SettingsStore backs the primary
    // server id, so it is always open.
    await SettingsStore.init(testEncKey);
    await BookmarkStore.init(testEncKey);
    await CompletedBooksStore.init(testEncKey);
    await WantToReadStore.init(testEncKey);
    await NamedBookmarkStore.init(testEncKey);
    await TimelineQueueStore.init(testEncKey);
    await TrackCacheStore.init(testEncKey);
    await NarratorIndexStore.init(testEncKey);
    await PlaybackLogStore.init(testEncKey);
  }

  setUp(() async {
    dir = await startHiveTestEnv();
    ServerScope.debugReset();
    await initStores();
  });
  tearDown(() => stopHiveTestEnv(dir));

  BookPosition posAt(int ms) => BookPosition(
        trackRatingKey: 't1',
        positionMs: ms,
        absolutePositionMs: ms,
        savedAt: DateTime(2026, 8, 7),
      );

  group('one server — nothing changes', () {
    test('the first server writes unprefixed keys', () async {
      await ServerScope.configure('server-a');
      expect(ServerScope.key('12345'), '12345');
      expect(ServerScope.ratingKeyOf('12345'), '12345');
    });

    test('records written before scoping existed are still found', () async {
      // Exactly the upgrade path: a bare key already in the box, and the app
      // starting up on the same server it has always used.
      await ServerScope.configure(null); // nothing known yet
      await BookmarkStore.save('12345', posAt(60000));

      await ServerScope.configure('server-a'); // first server now known
      expect(BookmarkStore.load('12345')?.positionMs, 60000,
          reason: 'an upgrade must not strand an existing position');
      expect(BookmarkStore.allPositions().keys, contains('12345'));
    });

    test('signing out still reads the primary server\'s books', () async {
      await ServerScope.configure('server-a');
      await BookmarkStore.save('12345', posAt(120000));

      // clearAuth drops the machine identifier; downloaded books still play.
      await ServerScope.configure(null);
      expect(BookmarkStore.load('12345')?.positionMs, 120000);
    });

    test('signing out from a *secondary* server keeps that server\'s books',
        () async {
      await ServerScope.configure('server-a'); // primary
      await BookmarkStore.save('a-book', posAt(1000));
      await ServerScope.configure('server-b');
      await BookmarkStore.save('b-book', posAt(2000));

      // The downloads still on the phone are server B's — falling back to the
      // primary here made a secondary-server user's library invisible the
      // moment they signed out.
      await ServerScope.configure(null);
      expect(BookmarkStore.load('b-book')?.positionMs, 2000);
      expect(BookmarkStore.allPositions().keys, ['b-book']);
    });
  });

  group('two servers — no collision', () {
    test('the same rating key is a different book on each server', () async {
      await ServerScope.configure('server-a');
      await BookmarkStore.save('12345', posAt(3600000)); // an hour in

      await ServerScope.configure('server-b');
      expect(BookmarkStore.load('12345'), isNull,
          reason: 'a book never opened on this server must not be an hour in');

      await BookmarkStore.save('12345', posAt(5000));
      expect(BookmarkStore.load('12345')?.positionMs, 5000);

      // The first server's position survived being shadowed.
      await ServerScope.configure('server-a');
      expect(BookmarkStore.load('12345')?.positionMs, 3600000,
          reason: 'the other server must not have overwritten it');
    });

    test('Continue Listening never lists the other server\'s books', () async {
      await ServerScope.configure('server-a');
      await BookmarkStore.save('aaa', posAt(1000));

      await ServerScope.configure('server-b');
      await BookmarkStore.save('bbb', posAt(2000));

      expect(BookmarkStore.allPositions().keys, ['bbb']);
      expect(BookmarkStore.savedBookKeys(), {'bbb'});

      await ServerScope.configure('server-a');
      expect(BookmarkStore.allPositions().keys, ['aaa']);
    });

    test('finished on one server is not finished on the other', () async {
      await ServerScope.configure('server-a');
      await CompletedBooksStore.markCompleted('12345');
      expect(CompletedBooksStore.isCompleted('12345'), isTrue);

      await ServerScope.configure('server-b');
      expect(CompletedBooksStore.isCompleted('12345'), isFalse);
      expect(CompletedBooksStore.allCompleted(), isEmpty);

      await ServerScope.configure('server-a');
      expect(CompletedBooksStore.allCompleted(), {'12345'});
    });

    test('want-to-read is per server', () async {
      await ServerScope.configure('server-a');
      await WantToReadStore.toggle('12345');
      expect(WantToReadStore.isWanted('12345'), isTrue);

      await ServerScope.configure('server-b');
      expect(WantToReadStore.isWanted('12345'), isFalse);
      expect(WantToReadStore.all, isEmpty);
    });
  });

  group('the primary server is remembered', () {
    test('it is the first one seen, and it sticks', () async {
      await ServerScope.configure('server-a');
      expect(SettingsStore.primaryServerId, 'server-a');

      await ServerScope.configure('server-b');
      expect(SettingsStore.primaryServerId, 'server-a',
          reason: 'changing it would strand every record filed under it');
      expect(ServerScope.key('1'), 'server-b|1');

      await ServerScope.configure('server-a');
      expect(ServerScope.key('1'), '1');
    });
  });

  // The stores below all missed the original scoping pass — each of these
  // would have failed against 1.1.0 as first written. A store keyed by a
  // rating key (or any other per-server id) that skips ServerScope is the bug
  // these exist to keep out.
  group('the stores the first scoping pass missed', () {
    NamedBookmark bookmarkFor(String bookKey, {String label = 'mark'}) =>
        NamedBookmark(
          id: '$bookKey-$label',
          bookRatingKey: bookKey,
          trackRatingKey: 't1',
          positionMs: 1000,
          label: label,
          createdAt: DateTime(2026, 8, 8),
        );

    test('named bookmarks are per server', () async {
      await ServerScope.configure('server-a');
      await NamedBookmarkStore.save(bookmarkFor('12345'));

      await ServerScope.configure('server-b');
      expect(NamedBookmarkStore.getForBook('12345'), isEmpty,
          reason: "another server's book must not list this one's bookmarks");
      expect(NamedBookmarkStore.getAll(), isEmpty);

      await NamedBookmarkStore.save(bookmarkFor('12345', label: 'b-mark'));
      expect(NamedBookmarkStore.getForBook('12345'), hasLength(1));

      await ServerScope.configure('server-a');
      final own = NamedBookmarkStore.getForBook('12345');
      expect(own, hasLength(1));
      expect(own.single.label, 'mark');
      expect(own.single.bookRatingKey, '12345',
          reason: 'the scope prefix must never leak out of the store');
    });

    test('a named bookmark from before scoping still lists (upgrade path)',
        () async {
      await ServerScope.configure(null); // nothing known yet
      await NamedBookmarkStore.save(bookmarkFor('12345'));

      await ServerScope.configure('server-a'); // first server now known
      expect(NamedBookmarkStore.getForBook('12345'), hasLength(1));
    });

    test('the offline timeline queue is per server', () async {
      PendingTimeline pending(int ms) => PendingTimeline(
            ratingKey: 't1',
            key: '/library/parts/1',
            positionMs: ms,
            durationMs: 100000,
            state: 'paused',
            savedAt: DateTime(2026, 8, 8),
          );

      await ServerScope.configure('server-a');
      await TimelineQueueStore.enqueue('12345', pending(60000));

      await ServerScope.configure('server-b');
      expect(TimelineQueueStore.all(), isEmpty,
          reason: "a flush at server B must not replay server A's positions");

      await TimelineQueueStore.enqueue('12345', pending(5000));
      await ServerScope.configure('server-a');
      expect(TimelineQueueStore.all()['12345']?.positionMs, 60000,
          reason: "server B's enqueue must not overwrite server A's entry");
    });

    test('per-book playback speed is per server', () async {
      await ServerScope.configure('server-a');
      await SettingsStore.setBookSpeed('12345', 2.0);

      await ServerScope.configure('server-b');
      expect(SettingsStore.getBookSpeed('12345'), SettingsStore.defaultSpeed,
          reason: "another server's book 12345 has no saved speed");

      await SettingsStore.setBookSpeed('12345', 1.5);
      await ServerScope.configure('server-a');
      expect(SettingsStore.getBookSpeed('12345'), 2.0);
    });

    test('the narrator index is per section *and* server', () async {
      await ServerScope.configure('server-a');
      await NarratorIndexStore.save('1', {
        '12345': ['Narrator A'],
      });

      await ServerScope.configure('server-b');
      expect(NarratorIndexStore.has('1'), isFalse,
          reason: "section ids are per-server integers, like rating keys");
      expect(NarratorIndexStore.load('1'), isNull);

      // Building B's index must not destroy A's.
      await NarratorIndexStore.save('1', {
        '12345': ['Narrator B'],
      });
      await ServerScope.configure('server-a');
      expect(NarratorIndexStore.load('1')?['12345'], ['Narrator A']);
    });

    test('trackCount reads the same scoped record save wrote', () async {
      PlexTrack track(String rk) => PlexTrack(
            ratingKey: rk,
            key: '/library/metadata/$rk',
            title: 'Track',
            durationMs: 1000,
            index: 1,
            partKey: '/library/parts/$rk',
          );

      await ServerScope.configure('server-a'); // primary
      await ServerScope.configure('server-b'); // now on the second server
      await TrackCacheStore.save('12345', [track('t1'), track('t2')]);

      // The original code read trackCount by the *bare* key while save wrote
      // the scoped one, so on a second server this answered null — and the
      // downloaded badge fell back to "any file counts as fully downloaded".
      expect(TrackCacheStore.trackCount('12345'), 2);

      await ServerScope.configure('server-a');
      expect(TrackCacheStore.trackCount('12345'), isNull);
    });

    test('the playback log round-trips its compound keys per server', () async {
      AudioLogEvent event(int ms) => AudioLogEvent(
            type: 'play',
            trackRatingKey: 't1',
            positionMs: ms,
            timestamp: DateTime(2026, 8, 8),
          );

      await ServerScope.configure('server-a');
      PlaybackLogStore.log(bookRatingKey: '12345', event: event(1000));

      await ServerScope.configure('server-b');
      expect(PlaybackLogStore.getLog('12345'), isEmpty);
      expect(PlaybackLogStore.bookRatingKeys(), isEmpty);

      await ServerScope.configure('server-a');
      expect(PlaybackLogStore.getLog('12345'), hasLength(1));
      expect(PlaybackLogStore.bookRatingKeys(), contains('12345'));
    });
  });

  group('scoped records survive a cold restart', () {
    test('prefixed keys and the primary id read back from disk', () async {
      await ServerScope.configure('server-a');
      await BookmarkStore.save('12345', posAt(3600000));
      await ServerScope.configure('server-b');
      await BookmarkStore.save('12345', posAt(5000));

      await coldRestartHive();
      ServerScope.debugReset();
      await initStores();

      await ServerScope.configure('server-b');
      expect(BookmarkStore.load('12345')?.positionMs, 5000);
      await ServerScope.configure('server-a');
      expect(BookmarkStore.load('12345')?.positionMs, 3600000);
      expect(SettingsStore.primaryServerId, 'server-a');
    });
  });
}
