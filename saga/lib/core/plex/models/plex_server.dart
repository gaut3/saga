class PlexConnection {
  final String uri;
  final bool local;
  final bool relay;
  final bool https;

  const PlexConnection({
    required this.uri,
    required this.local,
    required this.relay,
    required this.https,
  });

  factory PlexConnection.fromJson(Map<String, dynamic> json) {
    return PlexConnection(
      // Tolerant: one connection without a uri must not kill the server list;
      // PlexServer.fromJson filters the empty ones out.
      uri: json['uri']?.toString() ?? '',
      local: json['local'] == true || json['local'] == 1,
      relay: json['relay'] == true || json['relay'] == 1,
      https: (json['protocol'] as String? ?? '') == 'https',
    );
  }

  int get priority {
    if (local && https) return 0;
    if (local && !https) return 1;
    if (!local && !relay && https) return 2;
    if (!local && !relay && !https) return 3;
    return 4; // relay
  }
}

class PlexServer {
  final String name;
  final String machineIdentifier;
  final List<PlexConnection> connections;

  PlexServer({
    required this.name,
    required this.machineIdentifier,
    required this.connections,
  });

  factory PlexServer.fromJson(Map<String, dynamic> json) {
    final rawConnections = json['connections'] as List<dynamic>? ?? [];
    final connections = [
      for (final c in rawConnections)
        if (c is Map<String, dynamic>) PlexConnection.fromJson(c)
    ].where((c) => c.uri.isNotEmpty).toList()
      ..sort((a, b) => a.priority.compareTo(b.priority));

    return PlexServer(
      name: json['name'] as String? ?? 'Plex server',
      // Deliberately still a hard cast: the machine identifier keys every
      // per-book store (ServerScope) — a defaulted value would scope data
      // under garbage. The throw is per-server: fetchServers drops this
      // entry and keeps the rest of the list.
      machineIdentifier: json['clientIdentifier'] as String,
      connections: connections,
    );
  }
}
