import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saga/core/plex/plex_client.dart';

/// Casting is the one path allowed to put a credential in a URL
/// (`media_browse_test` polices that exclusivity), and a Cast receiver's
/// status — `contentId` included — is readable unauthenticated by anything on
/// the LAN. So *which* credential goes in that URL, and into how many URLs,
/// is a security decision: a delegated token may ride along on artwork, the
/// account token must appear exactly once, artwork dropped. These tests pin
/// the fallback — the branch nothing else exercises.
void main() {
  const server = 'http://192.168.1.9:32400';
  const accountToken = 'ACCOUNT-TOKEN-SECRET';
  const delegatedToken = 'delegated-abc123';

  Dio dioAnswering(ResponseBody Function(RequestOptions) handler) {
    final dio = Dio();
    dio.httpClientAdapter = _FakeAdapter(handler);
    return dio;
  }

  ResponseBody json(Map<String, dynamic> body, {int status = 200}) =>
      ResponseBody.fromString(jsonEncode(body), status, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });

  test('a minted delegated token is used everywhere, the account token nowhere',
      () async {
    Uri? asked;
    final client = PlexClient.forTest(
      serverUri: server,
      token: accountToken,
      dio: dioAnswering((options) {
        asked = options.uri;
        return json({
          'MediaContainer': {'token': delegatedToken}
        });
      }),
    );

    final media = await client.buildCastMedia(
        partKey: '/library/parts/1/file.m4b', thumbPath: '/library/thumb/1');

    expect(asked?.path, '/security/token',
        reason: 'the delegated token must come from the Plex endpoint');
    expect(media, isNotNull);
    expect(media!.streamUrl, contains('X-Plex-Token=$delegatedToken'));
    expect(media.artUrl, isNotNull,
        reason: 'artwork costs nothing extra with a delegated token');
    expect(media.artUrl, contains('X-Plex-Token=$delegatedToken'));
    expect('${media.streamUrl} ${media.artUrl}',
        isNot(contains(accountToken)),
        reason: 'the account token must never reach a Cast URL '
            'when a delegated one exists');
  });

  test('an older server putting the token at the top level still counts',
      () async {
    final client = PlexClient.forTest(
      serverUri: server,
      token: accountToken,
      dio: dioAnswering((_) => json({'token': delegatedToken})),
    );

    final media = await client.buildCastMedia(
        partKey: '/library/parts/1/file.m4b', thumbPath: '/library/thumb/1');

    expect(media!.streamUrl, contains('X-Plex-Token=$delegatedToken'));
    expect(media.artUrl, contains('X-Plex-Token=$delegatedToken'));
  });

  test('a server that will not mint one: account token once, artwork dropped',
      () async {
    final client = PlexClient.forTest(
      serverUri: server,
      token: accountToken,
      // Non-2xx becomes a DioException inside the client — the refusal path.
      dio: dioAnswering((_) => json({}, status: 404)),
    );

    final media = await client.buildCastMedia(
        partKey: '/library/parts/1/file.m4b', thumbPath: '/library/thumb/1');

    expect(media, isNotNull, reason: 'casting still works, at a price');
    expect(media!.streamUrl, contains('X-Plex-Token=$accountToken'));
    expect(media.artUrl, isNull,
        reason: 'a second copy of the account token buys only a thumbnail — '
            'artwork must be dropped on the fallback');
  });

  test('a 200 with no token in it is the same refusal', () async {
    final client = PlexClient.forTest(
      serverUri: server,
      token: accountToken,
      dio: dioAnswering((_) => json({'MediaContainer': {}})),
    );

    final media = await client.buildCastMedia(
        partKey: '/library/parts/1/file.m4b', thumbPath: '/library/thumb/1');

    expect(media!.streamUrl, contains('X-Plex-Token=$accountToken'));
    expect(media.artUrl, isNull);
  });

  test('signed out or serverless builds nothing at all', () async {
    final noToken = PlexClient.forTest(
        serverUri: server,
        token: null,
        dio: dioAnswering((_) => json({'token': delegatedToken})));
    expect(await noToken.buildCastMedia(partKey: '/p'), isNull);

    final noServer = PlexClient.forTest(
        serverUri: null,
        token: accountToken,
        dio: dioAnswering((_) => json({'token': delegatedToken})));
    expect(await noServer.buildCastMedia(partKey: '/p'), isNull);
  });
}

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);
  final ResponseBody Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
          Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async =>
      handler(options);

  @override
  void close({bool force = false}) {}
}
