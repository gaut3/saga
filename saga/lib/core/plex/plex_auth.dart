import 'dart:async';

import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';

import 'plex_client.dart';

const _plexTvBase = 'https://plex.tv';

class PlexPinResult {
  final int id;
  final String code;

  const PlexPinResult({required this.id, required this.code});
}

class PlexAuth {
  final PlexClient _client;

  PlexAuth(this._client);

  // connectTimeout fails fast on an unreachable host; without it a stalled
  // TCP connect hangs the request (and the poll loop below) indefinitely.
  static final _dioOptions = BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
  );

  Future<PlexPinResult> requestPin() async {
    final response = await Dio(_dioOptions).post<Map<String, dynamic>>(
      '$_plexTvBase/api/v2/pins',
      queryParameters: {
        'strong': true,
        'X-Plex-Client-Identifier': _client.clientId,
        'X-Plex-Product': 'AudiobookPlex',
      },
      options: Options(headers: {'Accept': 'application/json'}),
    );

    final data = response.data!;
    return PlexPinResult(
      id: data['id'] as int,
      code: data['code'] as String,
    );
  }

  Future<void> openAuthUrl(PlexPinResult pin) async {
    final uri = Uri.parse(
      'https://app.plex.tv/auth/#!'
      '?clientID=${_client.clientId}'
      '&code=${pin.code}'
      '&context%5Bdevice%5D%5Bproduct%5D=AudiobookPlex',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Poll until the user completes auth or [timeout] elapses.
  /// Returns the auth token on success, null on timeout/cancel.
  Future<String?> pollForToken(
    PlexPinResult pin, {
    Duration timeout = const Duration(minutes: 5),
    Duration interval = const Duration(seconds: 2),
    void Function()? onTick,
  }) async {
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(interval);
      onTick?.call();

      try {
        final response = await Dio(_dioOptions).get<Map<String, dynamic>>(
          '$_plexTvBase/api/v2/pins/${pin.id}',
          queryParameters: {
            'X-Plex-Client-Identifier': _client.clientId,
          },
          options: Options(headers: {'Accept': 'application/json'}),
        );

        final authToken = response.data?['authToken'] as String?;
        if (authToken != null && authToken.isNotEmpty) {
          await _client.saveToken(authToken);
          return authToken;
        }
      } on DioException {
        // transient — keep polling
      }
    }

    return null;
  }
}
