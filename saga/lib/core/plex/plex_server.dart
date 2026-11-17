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
    // Per-entry tolerance: one malformed resource (e.g. a server record
    // without a clientIdentifier) used to empty the whole server list.
    final servers = <PlexServer>[];
    for (final r in resources) {
      if (r is! Map<String, dynamic>) continue;
      if (!(r['provides'] as String? ?? '').contains('server')) continue;
      try {
        servers.add(PlexServer.fromJson(r));
      } catch (e) {
        AppLog.log('server', 'skipped an unparseable server entry: $e');
      }
    }
    return servers;
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
  Future<String?> findReachableUri(PlexServer server) => selectReachable(
      server.connections,
      (uri) => _probe(uri,
          machineIdentifier: server.machineIdentifier,
          token: server.accessToken));

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

  /// Whether [uri] answers as **this** Plex server, without spending a token
  /// to find out.
  ///
  /// `/identity` is one of the few endpoints Plex serves unauthenticated, and
  /// this runs against every connection the account lists — local, remote,
  /// relay, plaintext — including the ones that are about to lose. Attaching a
  /// credential to all of them to discover which single one to use put it in
  /// far more places than the app ever goes on to talk to.
  ///
  /// The answer has to name [machineIdentifier]. A 200 alone used to do, so
  /// whatever answered at a listed address was taken for the server: a LAN
  /// address like 192.168.1.10:32400 is somebody else's Plex server in
  /// somebody else's house, and a plain-HTTP address proves nothing about
  /// who is behind it. The winner is sent the token on every request.
  ///
  /// A server that does demand auth here is retried once with its own
  /// [token], over HTTPS only, so a token never rides a plaintext probe; the
  /// log line says when that happened.
  Future<bool> _probe(String uri,
      {required String machineIdentifier, String? token}) async {
    // connectTimeout covers the TCP connect phase, which send/receive timeouts
    // do not — without it an unresponsive host hangs the probe.
    final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 5)));
    Future<Response<dynamic>> identity({required bool authenticated}) =>
        dio.get<dynamic>(
          '$uri/identity',
          options: Options(
            sendTimeout: const Duration(seconds: 5),
            receiveTimeout: const Duration(seconds: 5),
            // Probes are answered by whatever is at the address: no
            // redirects to follow, and nothing large to read.
            followRedirects: false,
            headers: {
              'Accept': 'application/json',
              if (authenticated && token != null) 'X-Plex-Token': token,
            },
            // Report the status instead of throwing on it, so 401 is a
            // decision to make rather than an exception to swallow.
            validateStatus: (_) => true,
          ),
        );

    try {
      var response = await identity(authenticated: false);
      final status = response.statusCode;
      if ((status == 401 || status == 403) &&
          token != null &&
          uri.startsWith('https://')) {
        AppLog.log('plex', '/identity refused an anonymous probe ($status) — '
            'retrying with the token');
        response = await identity(authenticated: true);
      }
      if (response.statusCode != 200) return false;
      if (identityNames(response.data, machineIdentifier)) return true;
      AppLog.log('server', 'a connection answered as a different server — '
          'skipped');
      return false;
    } catch (_) {
      return false;
    } finally {
      dio.close();
    }
  }

  /// Whether an `/identity` body names [machineIdentifier]: the JSON Plex
  /// sends when asked for it, or the XML an older server sends regardless.
  @visibleForTesting
  static bool identityNames(Object? body, String machineIdentifier) {
    if (body is Map) {
      final container = body['MediaContainer'];
      final id = container is Map ? container['machineIdentifier'] : null;
      return id == machineIdentifier;
    }
    if (body is String) {
      final match =
          RegExp(r'machineIdentifier="([^"]*)"').firstMatch(body);
      if (match != null) return match[1] == machineIdentifier;
      // JSON delivered as text (no JSON content type on the answer).
      return RegExp('"machineIdentifier"\\s*:\\s*"${RegExp.escape(machineIdentifier)}"')
          .hasMatch(body);
    }
    return false;
  }

  /// Picks the saved server's best reachable connection again, from a fresh
  /// list from plex.tv. Returns whether one answered; with none, the saved
  /// address is left as it was.
  ///
  /// One run at a time, shared by every caller: a network change, a cast that
  /// couldn't reach the server and a failed library load can all land within
  /// a second of each other, and each used to probe every connection itself.
  ///
  /// The answer can differ from the saved address without the server having
  /// moved: an address chosen away from home is often unreachable from inside
  /// it (most routers don't loop a request to their own public address back
  /// in), and nothing else ever asks again while the app is running.
  Future<bool> rediscover() {
    return _rediscovering ??=
        _rediscover().whenComplete(() => _rediscovering = null);
  }

  static Future<bool>? _rediscovering;

  Future<bool> _rediscover() async {
    // Without a token plex.tv answers 401, which reads as a revoked one.
    if (!_client.isAuthenticated) return false;
    final servers = await fetchServers();
    final saved = _client.machineIdentifier;
    final savedUri = _client.serverUri;
    // With no saved id (an install from before it was stored), the server is
    // the one that lists the saved address. Never "the first in the list":
    // that can be a server somebody else shared with this account.
    final server = saved == null
        ? servers
            .where((s) => s.connections.any((c) => c.uri == savedUri))
            .firstOrNull
        : servers.where((s) => s.machineIdentifier == saved).firstOrNull;
    if (server == null) {
      if (servers.isNotEmpty) {
        // The saved server is missing from the account's list. Plex lists
        // other people's shared servers here too, so adopting whichever one
        // comes first would silently re-point the app — and every per-server
        // store behind ServerScope — at somebody else's library, possibly with
        // a book still playing. Re-selecting a server is the user's call.
        AppLog.log('server',
            'saved server not in account list — not adopting another');
      }
      return false;
    }
    // The server's token is renewed even if no connection answers below: a
    // 401 from the server is one of the reasons this runs.
    if (saved != null) await _client.saveServerToken(server.accessToken);
    return selectServer(server);
  }

  /// Saves [server]'s best reachable connection. Returns whether one answered.
  Future<bool> selectServer(PlexServer server) async {
    final uri = await findReachableUri(server);
    // Individual probe failures are expected noise (most connections lose),
    // so the log line lives here, at the decision: "can't reach my server" is
    // the most likely diagnostics paste there is, and it used to say nothing.
    if (uri == null) {
      AppLog.log('server',
          'none of ${server.connections.length} connections reachable');
      return false;
    }
    final index = server.connections.indexWhere((c) => c.uri == uri);
    final conn = server.connections[index];
    final kind = conn.relay ? 'relay' : (conn.local ? 'local' : 'remote');
    AppLog.log('server',
        'selected connection ${index + 1}/${server.connections.length} '
        '($kind, ${conn.https ? 'https' : 'http'})');
    // The token before the address: the next request to the new address must
    // already carry this server's token, not the previous server's.
    await _client.saveServerToken(server.accessToken);
    await _client.saveServerUri(uri);
    await _client.saveMachineIdentifier(server.machineIdentifier);
    // Re-point per-book storage at the newly selected server before anything
    // reads it. Without this, this server's book 12345 would resume at the
    // previous server's book 12345 — see server_scope.dart.
    await ServerScope.configure(server.machineIdentifier);
    return true;
  }
}
