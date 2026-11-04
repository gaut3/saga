import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saga/core/plex/plex_client.dart';
import 'package:saga/core/plex/plex_server.dart';

/// [PlexServerDiscovery.rediscover] runs on every network change and on a
/// cast that can't reach the server, often several at once (#24).
void main() {
  test('callers at the same moment share one run', () async {
    var asked = 0;
    final client = PlexClient.forTest(
      serverUri: 'https://10-0-0-2.abc.plex.direct:32400',
      token: 'TOKEN',
      dio: Dio()
        ..httpClientAdapter = _FakeAdapter((_) {
          asked++;
          return ResponseBody.fromString(jsonEncode([]), 200, headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          });
        }),
    );
    final discovery = PlexServerDiscovery(client);

    final results = await Future.wait(
        [discovery.rediscover(), discovery.rediscover(), discovery.rediscover()]);

    expect(asked, 1);
    expect(results, everyElement(isFalse), reason: 'no server in the list');

    await discovery.rediscover();
    expect(asked, 2, reason: 'a finished run is not reused');
  });

  test('signed out, plex.tv is not asked', () async {
    // Its 401 to a tokenless request reads as a revoked token.
    var asked = 0;
    final client = PlexClient.forTest(
      serverUri: 'https://10-0-0-2.abc.plex.direct:32400',
      token: null,
      dio: Dio()
        ..httpClientAdapter = _FakeAdapter((_) {
          asked++;
          return ResponseBody.fromString('', 401);
        }),
    );

    expect(await PlexServerDiscovery(client).rediscover(), isFalse);
    expect(asked, 0);
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
