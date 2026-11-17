import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saga/core/plex/models/plex_book.dart';
import 'package:saga/core/plex/models/plex_track.dart';
import 'package:saga/core/plex/plex_api.dart';
import 'package:saga/core/plex/plex_client.dart';
import 'package:saga/core/plex/rating_key.dart';

void main() {
  test('what Plex mints is a rating key; path punctuation is not', () {
    for (final ok in ['42', '0', 'abc_DEF-9']) {
      expect(isRatingKey(ok), isTrue, reason: ok);
    }
    for (final bad in [
      '',
      '../1',
      '1/../../:/timeline?time=0&x=',
      '1?x',
      '1%2F',
      'server|12',
      '1 2',
      '1.2',
    ]) {
      expect(isRatingKey(bad), isFalse, reason: bad);
    }
  });

  test('a server path starts at the server', () {
    expect(serverPathOrNull('/library/parts/1/2/file.mp3'),
        '/library/parts/1/2/file.mp3');
    // `$serverUri$path`: without a leading slash these name another host.
    expect(serverPathOrNull('@evil.example/x'), isNull);
    expect(serverPathOrNull('.evil.example/x'), isNull);
    expect(serverPathOrNull('//evil.example/x'), isNull);
    expect(serverPathOrNull(null), isNull);
    expect(serverPathOrNull(7), isNull);
  });

  test('a track or book whose key is not a key fails to parse', () {
    expect(() => PlexTrack.fromJson({'ratingKey': '../Other Book/4711'}),
        throwsFormatException);
    expect(() => PlexTrack.fromJson({}), throwsFormatException);
    expect(() => PlexBook.fromJson({'ratingKey': 'a|b'}),
        throwsFormatException);
    expect(PlexTrack.fromJson({'ratingKey': 12}).ratingKey, '12');
  });

  test('a part or cover path that names another host is dropped', () {
    final track = PlexTrack.fromJson({
      'ratingKey': '1',
      'parentThumb': '@evil.example/thumb',
      'Media': [
        {
          'Part': [
            {'key': '@evil.example/audio.mp3'}
          ]
        }
      ],
    });
    expect(track.partKey, '');
    expect(track.thumbPath, isNull);
  });

  test('PlexApi sends no request for an id that is not one', () async {
    final dio = Dio();
    var requests = 0;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      requests++;
      h.reject(DioException(requestOptions: o));
    }));
    final api = PlexApi(PlexClient.forTest(
        dio: dio, serverUri: 'https://server.example:32400', token: 't'));
    await expectLater(
        api.fetchTracks('1/../../:/timeline?time=0&x='), throwsFormatException);
    await expectLater(api.fetchBooks('1/../x'), throwsFormatException);
    await expectLater(api.fetchBookMetadataRaw('1?x'), throwsFormatException);
    expect(requests, 0);
  });
}
