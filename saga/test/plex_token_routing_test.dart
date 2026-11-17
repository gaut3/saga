import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saga/core/plex/models/plex_server.dart';
import 'package:saga/core/plex/plex_client.dart';
import 'package:saga/core/plex/plex_server.dart';

/// Which credential a request carries is decided by where it is going. The
/// account token opens the whole Plex account, so it goes to plex.tv only;
/// a media server (which may be one somebody else shared) gets its own.
void main() {
  const server = 'https://10-0-0-2.abc.plex.direct:32400';

  ({PlexClient client, List<RequestOptions> seen}) make(
      {String? serverToken, int status = 200}) {
    final seen = <RequestOptions>[];
    final client = PlexClient.forTest(
      serverUri: server,
      token: 'ACCOUNT',
      serverToken: serverToken,
      dio: Dio()
        ..httpClientAdapter = _FakeAdapter((o) {
          seen.add(o);
          return ResponseBody.fromString(jsonEncode({}), status, headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          });
        }),
    );
    return (client: client, seen: seen);
  }

  test('the media server gets its own token, never the account token',
      () async {
    final t = make(serverToken: 'SERVER');
    await t.client.get<dynamic>('/library/sections');
    expect(t.seen.single.headers['X-Plex-Token'], 'SERVER');
    expect(t.client.authHeaders, {'X-Plex-Token': 'SERVER'});
  });

  test('plex.tv gets the account token', () async {
    final t = make(serverToken: 'SERVER');
    await t.client
        .get<dynamic>('/api/v2/resources', baseUrl: 'https://plex.tv');
    expect(t.seen.single.headers['X-Plex-Token'], 'ACCOUNT');
  });

  test('any other host gets no credential', () async {
    final t = make(serverToken: 'SERVER');
    await t.client.get<dynamic>('/x', baseUrl: 'https://elsewhere.example');
    // Same host as the server, another port: still not the server.
    await t.client
        .get<dynamic>('/x', baseUrl: 'https://10-0-0-2.abc.plex.direct:8443');
    // A name that only ends like plex.tv.
    await t.client.get<dynamic>('/x', baseUrl: 'https://not-plex.tv');
    for (final o in t.seen) {
      expect(o.headers.containsKey('X-Plex-Token'), isFalse,
          reason: '${o.uri}');
    }
  });

  test('before a server token is stored, the account token stands in',
      () async {
    final t = make();
    expect(t.client.hasServerToken, isFalse);
    await t.client.get<dynamic>('/library/sections');
    expect(t.seen.single.headers['X-Plex-Token'], 'ACCOUNT');
  });

  test('a 401 from the media server asks plex.tv and keeps the session',
      () async {
    final t = make(serverToken: 'SERVER', status: 401);
    var signedOut = 0;
    var asked = 0;
    t.client.onUnauthorized = () => signedOut++;
    t.client.onServerUnauthorized = () => asked++;
    for (var i = 0; i < 3; i++) {
      await expectLater(t.client.get<dynamic>('/library/sections'),
          throwsA(isA<DioException>()));
    }
    expect(signedOut, 0);
    expect(asked, 1, reason: 'at most once a minute');
    expect(t.client.isAuthenticated, isTrue);
  });

  test('developer options can say which key is sent without showing one', () {
    final own = make(serverToken: 'SERVER').client.connectionFacts!;
    expect(own.serverKeyStored, isTrue);
    expect(own.sameAsAccountKey, isFalse);
    expect(own.encrypted, isTrue);
    expect(own.plexDirect, isTrue);

    final same = make(serverToken: 'ACCOUNT').client.connectionFacts!;
    expect(same.serverKeyStored, isTrue);
    expect(same.sameAsAccountKey, isTrue);

    final none = make().client.connectionFacts!;
    expect(none.serverKeyStored, isFalse);
  });

  test('the server list carries each server\'s token and whose it is', () {
    final mine = PlexServer.fromJson({
      'name': 'Home',
      'clientIdentifier': 'abc',
      'accessToken': 'SERVER',
      'owned': true,
      'connections': <dynamic>[],
    });
    final theirs = PlexServer.fromJson(
        {'clientIdentifier': 'def', 'owned': false, 'connections': <dynamic>[]});
    expect(mine.accessToken, 'SERVER');
    expect(mine.owned, isTrue);
    expect(theirs.accessToken, isNull);
    expect(theirs.owned, isFalse);
  });

  test('a probe answer must name the server it was sent to find', () {
    bool names(Object? body) =>
        PlexServerDiscovery.identityNames(body, 'abc');
    expect(
        names({
          'MediaContainer': {'machineIdentifier': 'abc'}
        }),
        isTrue);
    expect(
        names({
          'MediaContainer': {'machineIdentifier': 'someone-elses'}
        }),
        isFalse);
    expect(names('<MediaContainer machineIdentifier="abc" version="1"/>'),
        isTrue);
    expect(names('<MediaContainer machineIdentifier="xyz"/>'), isFalse);
    expect(names('{"MediaContainer":{"machineIdentifier": "abc"}}'), isTrue);
    // A captive portal, a router's page, nothing at all.
    expect(names('<html>Sign in to Wi-Fi</html>'), isFalse);
    expect(names(null), isFalse);
    expect(names({}), isFalse);
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
