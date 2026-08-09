import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../diagnostics/app_log.dart';
import '../storage/server_scope.dart';
import 'models/plex_server.dart';
import 'plex_client.dart';

class PlexServerDiscovery {
  final PlexClient _client;

  PlexServerDiscovery(this._client);

  Future<List<PlexServer>> fetchServers() async {
    final response = await _client.get<List<dynamic>>(
      '/api/v2/resources',
      baseUrl: 'https://plex.tv',
      queryParameters: {
        'includeHttps': 1,
        'includeRelay': 1,
        'includeIPv6': 1,
      },
    );

    final resources = response.data ?? [];
    return resources
        .where((r) => (r['provides'] as String? ?? '').contains('server'))
        .map((r) => PlexServer.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Probes every connection in parallel and returns the **best** reachable
  /// one, by [PlexConnection.priority] — HTTPS on the LAN ahead of plaintext,
  /// plaintext ahead of relay.
  ///
  /// The obvious version of this — complete on the first probe that answers —
  /// picks the quickest, not the best, and those are rarely the same: a
  /// plaintext LAN address answers before an HTTPS one can finish a DNS lookup
  /// and a TLS handshake. The winner here is saved as the server URI and every
  /// later request carries `X-Plex-Token` against it, so losing that race means
  /// an account-wide credential going out in the clear for as long as the
  /// choice stands. Sorting the list was never enough: it only decided the
  /// order the probes *started*, microseconds apart.
  ///
  /// So results are recorded by position and the decision is made by walking
  /// the priority order from the front, which also means no waiting once the
  /// answer can't change — a reachable top choice returns immediately.
  Future<String?> findReachableUri(PlexServer server) =>
      selectReachable(server.connections, _probe);

  /// The selection itself, with [probe] injected — this is the part that had
  /// the bug, and it is decided entirely by which probes answer and in what
  /// order, so it is tested without a network.
  ///
  /// [connections] must already be in priority order (`PlexServer.fromJson`
  /// sorts them).
  @visibleForTesting
  static Future<String?> selectReachable(
    List<PlexConnection> connections,
    Future<bool> Function(String uri) probe,
  ) {
    if (connections.isEmpty) return Future.value(null);

    final completer = Completer<String?>();
    // Indexed by the priority-sorted list: null while a probe is still in
    // flight, true/false once it has answered.
    final results = List<bool?>.filled(connections.length, null);

    void settle(int index, bool reachable) {
      if (completer.isCompleted) return;
      results[index] = reachable;
      for (var i = 0; i < results.length; i++) {
        // Still in flight, and better than anything decided so far — a better
        // answer may yet arrive, so nothing can be concluded.
        if (results[i] == null) return;
        if (results[i] == true) {
          completer.complete(connections[i].uri);
          return;
        }
      }
      completer.complete(null); // every connection failed
    }

    for (var i = 0; i < connections.length; i++) {
      final index = i;
      // The production probe never throws (it catches everything and answers
      // false), but a slot that never settles hangs the whole selection — so a
      // throwing probe counts as unreachable rather than relying on that.
      probe(connections[index].uri)
          .then((ok) => settle(index, ok))
          .catchError((_) => settle(index, false));
    }

    return completer.future;
  }

  /// Whether [uri] answers as a Plex server, **without spending the token to
  /// find out**.
  ///
  /// `/identity` is one of the few endpoints Plex serves unauthenticated, and
  /// this runs against every connection the account lists — local, remote,
  /// relay, plaintext — including the ones that are about to lose. Attaching an
  /// account-wide credential to all of them to discover which single one to use
  /// put it in far more places than the app ever goes on to talk to.
  ///
  /// A server that does demand auth here is retried once with the token rather
  /// than dropped, so this can't quietly cost anyone their connection; the log
  /// line says when that happened.
  Future<bool> _probe(String uri) async {
    // connectTimeout covers the TCP connect phase, which send/receive timeouts
    // do not — without it an unresponsive host hangs the probe.
    final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 5)));
    Future<int?> identity({required bool authenticated}) async {
      final response = await dio.get<dynamic>(
        '$uri/identity',
        options: Options(
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
          headers: {
            'Accept': 'application/json',
            if (authenticated) ..._client.authHeaders,
          },
          // Report the status instead of throwing on it, so 401 is a decision
          // to make rather than an exception to swallow.
          validateStatus: (_) => true,
        ),
      );
      return response.statusCode;
    }

    try {
      final status = await identity(authenticated: false);
      if (status == 200) return true;
      if (status == 401 || status == 403) {
        AppLog.log('plex', '/identity refused an anonymous probe ($status) — '
            'retrying with the token');
        return await identity(authenticated: true) == 200;
      }
      return false;
    } catch (_) {
      return false;
    } finally {
      dio.close();
    }
  }

  Future<void> selectServer(PlexServer server) async {
    final uri = await findReachableUri(server);
    if (uri != null) {
      await _client.saveServerUri(uri);
      await _client.saveMachineIdentifier(server.machineIdentifier);
      // Re-point per-book storage at the newly selected server before anything
      // reads it. Without this, this server's book 12345 would resume at the
      // previous server's book 12345 — see server_scope.dart.
      await ServerScope.configure(server.machineIdentifier);
    }
  }
}
