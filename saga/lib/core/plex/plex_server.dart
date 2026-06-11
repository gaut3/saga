import 'dart:async';

import 'package:dio/dio.dart';

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

  /// Try all connection URLs in parallel and return the first reachable one.
  /// Connections are sorted by priority so the best one wins if multiple succeed.
  Future<String?> findReachableUri(PlexServer server) async {
    if (server.connections.isEmpty) return null;

    final completer = Completer<String?>();
    var remaining = server.connections.length;

    void onResult(String? uri) {
      if (uri != null && !completer.isCompleted) {
        completer.complete(uri);
      }
      remaining--;
      if (remaining == 0 && !completer.isCompleted) {
        completer.complete(null);
      }
    }

    for (final connection in server.connections) {
      // connectTimeout covers the TCP connect phase, which send/receive
      // timeouts do not — without it an unresponsive host hangs the probe.
      Dio(BaseOptions(connectTimeout: const Duration(seconds: 5)))
          .get<dynamic>(
            '${connection.uri}/identity',
            options: Options(
              sendTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 5),
              headers: {
                'Accept': 'application/json',
                ..._client.authHeaders,
              },
            ),
          )
          .then((r) => onResult(r.statusCode == 200 ? connection.uri : null))
          .catchError((_) => onResult(null));
    }

    return completer.future;
  }

  Future<void> selectServer(PlexServer server) async {
    final uri = await findReachableUri(server);
    if (uri != null) {
      await _client.saveServerUri(uri);
      await _client.saveMachineIdentifier(server.machineIdentifier);
    }
  }
}
