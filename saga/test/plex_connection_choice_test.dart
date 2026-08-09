import 'package:flutter_test/flutter_test.dart';
import 'package:saga/core/plex/models/plex_server.dart';
import 'package:saga/core/plex/plex_server.dart';

/// Which connection the app settles on is a security decision, not just a
/// performance one: the winner becomes the server URI, and every request after
/// it carries an account-wide `X-Plex-Token` against that address. Picking a
/// plaintext connection when an HTTPS one was available puts that token on the
/// wire in the clear for as long as the choice stands.
///
/// The bug these cover: the old code completed on the *first probe to answer*,
/// which is the quickest and rarely the best — a plaintext LAN address replies
/// before an HTTPS one has finished a DNS lookup and a TLS handshake. Sorting
/// the list didn't help; it only set the order the probes started.
void main() {
  PlexConnection conn(String uri,
          {bool local = false, bool relay = false, bool https = false}) =>
      PlexConnection(uri: uri, local: local, relay: relay, https: https);

  /// A probe that answers [reachable] after [afterMs] of simulated latency.
  Future<bool> Function(String) probes(Map<String, (int, bool)> plan) =>
      (uri) async {
        final entry = plan[uri]!;
        await Future<void>.delayed(Duration(milliseconds: entry.$1));
        return entry.$2;
      };

  test('a slow HTTPS connection beats a fast plaintext one', () async {
    final connections = [
      conn('https://secure.example:32400', local: true, https: true),
      conn('http://192.0.2.10:32400', local: true),
    ];
    final chosen = await PlexServerDiscovery.selectReachable(
      connections,
      probes({
        'https://secure.example:32400': (60, true),
        'http://192.0.2.10:32400': (1, true), // answers first
      }),
    );
    expect(chosen, 'https://secure.example:32400');
  });

  test('the next best is taken when the best is unreachable', () async {
    final connections = [
      conn('https://secure.example:32400', local: true, https: true),
      conn('http://192.0.2.10:32400', local: true),
      conn('https://relay.example', relay: true, https: true),
    ];
    final chosen = await PlexServerDiscovery.selectReachable(
      connections,
      probes({
        'https://secure.example:32400': (5, false),
        'http://192.0.2.10:32400': (40, true),
        'https://relay.example': (1, true), // answers first, worst priority
      }),
    );
    expect(chosen, 'http://192.0.2.10:32400');
  });

  test('the best connection returns without waiting for the rest', () async {
    // A correct answer that always costs the slowest probe would be its own
    // regression — nothing better can beat the top choice, so nothing waits.
    final connections = [
      conn('https://secure.example:32400', local: true, https: true),
      conn('https://relay.example', relay: true, https: true),
    ];
    final started = DateTime.now();
    final chosen = await PlexServerDiscovery.selectReachable(
      connections,
      probes({
        'https://secure.example:32400': (1, true),
        'https://relay.example': (3000, true),
      }),
    );
    expect(chosen, 'https://secure.example:32400');
    expect(DateTime.now().difference(started).inMilliseconds, lessThan(1000));
  });

  test('every connection failing is null, not a hang', () async {
    final connections = [
      conn('https://secure.example:32400', local: true, https: true),
      conn('http://192.0.2.10:32400', local: true),
    ];
    final chosen = await PlexServerDiscovery.selectReachable(
      connections,
      probes({
        'https://secure.example:32400': (5, false),
        'http://192.0.2.10:32400': (1, false),
      }),
    );
    expect(chosen, isNull);
  });

  test('no connections at all is null', () async {
    expect(await PlexServerDiscovery.selectReachable([], (_) async => true),
        isNull);
  });

  test('parsing orders connections so the safest is tried first', () {
    // selectReachable trusts this order; it is what makes "first index that
    // succeeded" mean "best".
    final server = PlexServer.fromJson({
      'name': 'Tower',
      'clientIdentifier': 'abc',
      'connections': [
        {'uri': 'https://relay.example', 'relay': true, 'protocol': 'https'},
        {'uri': 'http://192.0.2.10:32400', 'local': true, 'protocol': 'http'},
        {
          'uri': 'https://secure.example:32400',
          'local': true,
          'protocol': 'https'
        },
      ],
    });
    expect([for (final c in server.connections) c.uri], [
      'https://secure.example:32400',
      'http://192.0.2.10:32400',
      'https://relay.example',
    ]);
  });
}
