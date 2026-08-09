import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saga/core/plex/models/plex_track.dart';
import 'package:saga/core/storage/book_download_store.dart';
import 'package:saga/core/storage/book_metadata_store.dart';
import 'package:saga/core/storage/bookmark_store.dart';
import 'package:saga/core/storage/completed_books_store.dart';
import 'package:saga/core/storage/custom_collection_store.dart';
import 'package:saga/core/storage/track_cache_store.dart';
import 'package:saga/features/player/media_browse.dart';

import 'helpers/hive_test_env.dart';

/// The browse tree is the one part of Saga its owner cannot try out — it is
/// only ever walked by a car head unit, the assistant, or Android's own
/// resumption card. So the rules it has to keep are pinned here instead:
///
///  - a media id we didn't mint never resolves to a book to play,
///  - `recent` answers with the book Continue Listening would offer,
///  - a book too anonymous to name is dropped rather than shown blank,
///  - and none of it needs the network, because a car doesn't have the server.
void main() {
  late Directory dir;

  setUp(() async {
    dir = await startHiveTestEnv();
    await BookmarkStore.init(testEncKey);
    await BookMetadataStore.init(testEncKey);
    await BookDownloadStore.init(testEncKey);
    await CompletedBooksStore.init(testEncKey);
    await CustomCollectionStore.init(testEncKey);
    await TrackCacheStore.init(testEncKey);
  });

  tearDown(() => stopHiveTestEnv(dir));

  Future<void> saveBook(
    String key, {
    required String title,
    String author = 'An author',
    DateTime? listenedAt,
  }) async {
    await BookMetadataStore.save(key, {
      'ratingKey': int.parse(key),
      'title': title,
      'parentTitle': author,
    });
    if (listenedAt != null) {
      await BookmarkStore.save(
        key,
        BookPosition(
          trackRatingKey: '$key-1',
          positionMs: 1000,
          absolutePositionMs: 1000,
          savedAt: listenedAt,
        ),
      );
    }
  }

  List<String> titles(List<dynamic> items) =>
      [for (final i in items) i.title as String];

  group('media ids', () {
    test('only ids we minted resolve to a book', () {
      expect(BrowseId.bookKeyOf(BrowseId.book('42')), '42');
      // The ids Android hands back are not all ours — a category, a collection
      // node, or something from another app's session must never be mistaken
      // for a book to start playing.
      expect(BrowseId.bookKeyOf(BrowseId.root), isNull);
      expect(BrowseId.bookKeyOf(BrowseId.recent), isNull);
      expect(BrowseId.bookKeyOf(BrowseId.continuing), isNull);
      expect(BrowseId.bookKeyOf(BrowseId.collection('c1')), isNull);
      expect(BrowseId.bookKeyOf(''), isNull);
    });

    test('collection ids round-trip and do not collide with books', () {
      expect(BrowseId.collectionIdOf(BrowseId.collection('c1')), 'c1');
      expect(BrowseId.collectionIdOf(BrowseId.book('42')), isNull);
    });

    test('a rating key containing the prefix survives the round trip', () {
      // Plex keys are numeric today, but a parser that splits on the first
      // slash would quietly mangle anything else.
      expect(BrowseId.bookKeyOf(BrowseId.book('book7')), 'book7');
      expect(BrowseId.bookKeyOf(BrowseId.book('abc_DEF-9')), 'abc_DEF-9');
    });

    test('a key that could be read as a path is not a book', () {
      // The browse service is exported and audio_service hands a browsable
      // root to every caller, so any app on the device can put a media id in
      // front of us. The key lands in a server URL — /library/metadata/$key/
      // children — which makes it the one part of that URL from outside.
      for (final hostile in [
        'book/../../security/token',
        'book/1?X-Plex-Token=stolen',
        'book/1/../..',
        'book/%2e%2e%2fsecurity',
        'book/1 2',
      ]) {
        expect(BrowseId.bookKeyOf(hostile), isNull, reason: hostile);
      }
    });
  });

  group('root', () {
    test('offers the three shelves, all browsable', () {
      final root = browseChildren(BrowseId.root);
      expect(titles(root),
          ['Continue listening', 'Downloaded', 'Collections']);
      expect(root.every((i) => i.playable == false), isTrue);
    });

    test('an unknown parent is empty, not an error', () {
      expect(browseChildren('nonsense/id'), isEmpty);
      expect(browseChildren(BrowseId.collection('gone')), isEmpty);
    });
  });

  group('recent — the resumption card', () {
    test('is empty when nothing has been listened to', () {
      expect(browseChildren(BrowseId.recent), isEmpty);
    });

    test('answers with the most recently listened book, and only that one',
        () async {
      await saveBook('1',
          title: 'Older', listenedAt: DateTime(2026, 8, 1));
      await saveBook('2',
          title: 'Newest', listenedAt: DateTime(2026, 8, 3));
      await saveBook('3',
          title: 'Middle', listenedAt: DateTime(2026, 8, 2));

      final recent = browseChildren(BrowseId.recent);
      expect(titles(recent), ['Newest']);
      expect(recent.single.playable, isTrue);
      // The card's play button hands this id straight back to us.
      expect(BrowseId.bookKeyOf(recent.single.id), '2');
    });
  });

  group('continue listening', () {
    test('is ordered by when each book was last heard, newest first',
        () async {
      await saveBook('1', title: 'B', listenedAt: DateTime(2026, 8, 1));
      await saveBook('2', title: 'C', listenedAt: DateTime(2026, 8, 3));
      await saveBook('3', title: 'A', listenedAt: DateTime(2026, 8, 2));

      expect(titles(browseChildren(BrowseId.continuing)), ['C', 'A', 'B']);
    });

    test('is capped, and the cap keeps the most recent', () async {
      for (var i = 0; i < 30; i++) {
        await saveBook('$i',
            title: 'Book $i', listenedAt: DateTime(2026, 1, 1).add(Duration(days: i)));
      }
      final items = browseChildren(BrowseId.continuing);
      expect(items.length, 25);
      expect(items.first.title, 'Book 29');
      expect(items.last.title, 'Book 5');
    });
  });

  group('naming a book', () {
    test('falls back to the cached tracks when the full record was never '
        'fetched', () async {
      // A book played straight from a list never has its detail screen opened,
      // so BookMetadataStore has nothing for it.
      await TrackCacheStore.save('9', const [
        PlexTrack(
          ratingKey: '9-1',
          key: '/library/metadata/9-1',
          title: 'Chapter 1',
          bookTitle: 'Named by its tracks',
          authorName: 'Track Author',
          durationMs: 60000,
          index: 1,
          partKey: '/parts/1',
        ),
        PlexTrack(
          ratingKey: '9-2',
          key: '/library/metadata/9-2',
          title: 'Chapter 2',
          bookTitle: 'Named by its tracks',
          durationMs: 30000,
          index: 2,
          partKey: '/parts/2',
        ),
      ]);
      await BookmarkStore.save(
        '9',
        BookPosition(
          trackRatingKey: '9-1',
          positionMs: 0,
          absolutePositionMs: 0,
          savedAt: DateTime(2026, 8, 3),
        ),
      );

      final item = browseChildren(BrowseId.continuing).single;
      expect(item.title, 'Named by its tracks');
      expect(item.artist, 'Track Author');
      // Length is summed across the files, not taken from the first.
      expect(item.duration, const Duration(milliseconds: 90000));
    });

    test('a book with no name anywhere is dropped, not shown blank', () async {
      // An unlabelled row is a button someone presses while driving without
      // knowing what it is.
      await BookmarkStore.save(
        'ghost',
        BookPosition(
          trackRatingKey: 'ghost-1',
          positionMs: 0,
          absolutePositionMs: 0,
          savedAt: DateTime(2026, 8, 3),
        ),
      );
      expect(browseChildren(BrowseId.continuing), isEmpty);
      expect(browseChildren(BrowseId.recent), isEmpty);
    });
  });

  group('downloaded', () {
    test('lists downloaded books alphabetically', () async {
      await saveBook('1', title: 'Zebra');
      await saveBook('2', title: 'apple');
      await saveBook('3', title: 'Mango');
      BookDownloadStore.recordDownload('1', '1-1');
      BookDownloadStore.recordDownload('2', '2-1');
      BookDownloadStore.recordDownload('3', '3-1');

      // Case-insensitive: 'apple' before 'Mango', not after 'Zebra'.
      expect(titles(browseChildren(BrowseId.downloaded)),
          ['apple', 'Mango', 'Zebra']);
    });
  });

  group('collections', () {
    test('keep the order the listener dragged them into', () async {
      await saveBook('1', title: 'Book One');
      await saveBook('2', title: 'Book Two');
      await saveBook('3', title: 'Book Three');
      final col = await CustomCollectionStore.create('Wheel of Time');
      // Deliberately not alphabetical and not insertion-sorted — reading order.
      await CustomCollectionStore.addBook(col.id, '3');
      await CustomCollectionStore.addBook(col.id, '1');
      await CustomCollectionStore.addBook(col.id, '2');

      expect(titles(browseChildren(BrowseId.collections)), ['Wheel of Time']);
      expect(titles(browseChildren(BrowseId.collection(col.id))),
          ['Book Three', 'Book One', 'Book Two']);
    });
  });

  group('search', () {
    setUp(() async {
      await saveBook('1',
          title: 'The Eye of the World',
          author: 'Robert Jordan',
          listenedAt: DateTime(2026, 8, 1));
      await saveBook('2',
          title: 'Dune',
          author: 'Frank Herbert',
          listenedAt: DateTime(2026, 8, 2));
    });

    test('matches title and author, case-insensitively', () {
      expect(titles(searchBooks('eye of')), ['The Eye of the World']);
      expect(titles(searchBooks('JORDAN')), ['The Eye of the World']);
      expect(titles(searchBooks('herbert')), ['Dune']);
    });

    test('an empty or unmatched query returns nothing', () {
      expect(searchBooks(''), isEmpty);
      expect(searchBooks('   '), isEmpty);
      expect(searchBooks('no such book'), isEmpty);
    });

    test('a book in two places is offered once', () async {
      BookDownloadStore.recordDownload('2', '2-1');
      final col = await CustomCollectionStore.create('Favourites');
      await CustomCollectionStore.addBook(col.id, '2');

      expect(titles(searchBooks('dune')), ['Dune']);
    });
  });

  group('nothing handed to the platform carries the Plex token', () {
    // Saga's `MediaBrowserService` is exported (a head unit has to be able to
    // bind) and `audio_service` answers `onGetRoot` for every caller — its
    // package check is commented out upstream, because it cannot consult Dart
    // synchronously. So any installed app can read these items back having
    // declared no permission, and the Plex token is account-wide.
    //
    // `PlexClient.buildCastMedia` is now the only thing in the app that puts a
    // credential in a URL, and it exists for the one consumer that cannot send
    // a header. Nothing that hands data to the platform may call it, and no
    // file here may assemble such a URL by hand.
    //
    // This is asserted against the source rather than the values because the
    // leak is invisible at runtime here: with no `ArtworkCache` directory and
    // no `PlexClient` instance in a unit test, both the correct and the broken
    // version return null. A behavioural test would pass either way, and the
    // one machine that would show the difference is a car.
    const rule =
        'must not build a token-bearing URL — see PlexClient.buildCastMedia';

    /// The file's code with comment-only lines dropped, so that *documenting*
    /// this rule doesn't trip it.
    String code(String path) => File(path)
        .readAsLinesSync()
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');

    /// The two ways a token reaches a URL: calling the builder that makes one,
    /// or writing the query parameter by hand.
    void expectNoTokenBearingUrl(String path, String who) {
      final src = code(path);
      expect(src, isNot(contains('buildCastMedia')), reason: '$who $rule');
      expect(src, isNot(contains('X-Plex-Token')), reason: '$who $rule');
    }

    test('the browse tree never asks for an authenticated artwork URL', () {
      expectNoTokenBearingUrl(
          'lib/features/player/media_browse.dart', 'media_browse');
    });

    test('now-playing metadata never asks for one either', () {
      // `_trackToMediaItem` feeds the platform MediaSession, which any app
      // holding notification access can read. `_prefetchArtwork` caches the
      // cover with header auth and re-emits the item, so the URL is never
      // needed.
      expectNoTokenBearingUrl(
          'lib/features/player/player_service.dart', '_trackToMediaItem');
    });

    test('in-app covers authenticate by header, not by URL', () {
      // Not a platform surface, but the same rule for a different reason:
      // CachedNetworkImage keys its on-disk cache by URL, so a token in the
      // query string is a token written to an unencrypted database and left
      // there after sign-out.
      expectNoTokenBearingUrl(
          'lib/shared/widgets/book_cover_image.dart', 'BookCoverImage');
      expectNoTokenBearingUrl(
          'lib/features/authors/authors_screen.dart', 'authors_screen');
    });
  });

  test('the tree survives a cold restart', () async {
    await saveBook('1', title: 'Persisted', listenedAt: DateTime(2026, 8, 3));
    await coldRestartHive();
    await BookmarkStore.init(testEncKey);
    await BookMetadataStore.init(testEncKey);
    await BookDownloadStore.init(testEncKey);
    await CompletedBooksStore.init(testEncKey);
    await CustomCollectionStore.init(testEncKey);
    await TrackCacheStore.init(testEncKey);

    expect(titles(browseChildren(BrowseId.recent)), ['Persisted']);
  });
}
