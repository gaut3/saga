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
        // The name this install signs in under — it is what the device list in
        // a Plex account shows, and the privacy policy says that entry reads
        // "Saga". ("AudiobookPlex" was the project's working title; existing
        // installs re-using the same client id keep their existing entry.)
        'X-Plex-Product': 'Saga',
      },
      options: Options(headers: {'Accept': 'application/json'}),
    );

    // A captive portal or proxy can answer for plex.tv with anything — fail
    // with something the sign-in screen can show, not a raw null-check throw.
    final data = response.data;
    final id = (data?['id'] as num?)?.toInt();
    final code = data?['code']?.toString();
    if (id == null || code == null || code.isEmpty) {
      throw const FormatException('plex.tv returned an unusable PIN response');
    }
    return PlexPinResult(id: id, code: code);
  }

  Future<void> openAuthUrl(PlexPinResult pin) async {
    final uri = Uri.parse(
      'https://app.plex.tv/auth/#!'
      '?clientID=${_client.clientId}'
      '&code=${pin.code}'
      '&context%5Bdevice%5D%5Bproduct%5D=Saga',
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
    // One client for the whole poll rather than one per tick: at a 2 s
    // interval across a 5 minute window that was up to 150 of them, each with
    // its own connection pool left to fall idle in its own time — during
    // sign-in, the one moment the listener is sat watching a spinner.
    final dio = Dio(_dioOptions);

    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(interval);
      onTick?.call();

      try {
        final response = await dio.get<Map<String, dynamic>>(
          '$_plexTvBase/api/v2/pins/${pin.id}',
          queryParameters: {
            'X-Plex-Client-Identifier': _client.clientId,
          },
          options: Options(headers: {'Accept': 'application/json'}),
        );

        final authToken = response.data?['authToken'] as String?;
        if (authToken != null && authToken.isNotEmpty) {
          await _client.saveToken(authToken);
          dio.close();
          return authToken;
        }
      } on DioException {
        // transient — keep polling
      } catch (_) {
        // A malformed response (captive portal, proxy) is transient too: the
        // deadline bounds the loop. Only DioException used to be caught, so
        // one odd body ended the whole sign-in poll.
      }
    }

    dio.close();
    return null;
  }
}
