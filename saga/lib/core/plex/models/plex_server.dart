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
      uri: json['uri'] as String,
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
  String? activeUri;

  PlexServer({
    required this.name,
    required this.machineIdentifier,
    required this.connections,
    this.activeUri,
  });

  factory PlexServer.fromJson(Map<String, dynamic> json) {
    final rawConnections = json['connections'] as List<dynamic>? ?? [];
    final connections = rawConnections
        .map((c) => PlexConnection.fromJson(c as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.priority.compareTo(b.priority));

    return PlexServer(
      name: json['name'] as String,
      machineIdentifier: json['clientIdentifier'] as String,
      connections: connections,
    );
  }
}
