import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saga/core/plex/plex_auth.dart';
import 'package:saga/core/plex/plex_client.dart';

/// The sign-in screen polls two PINs once it offers a plex.tv/link code; the
/// first to succeed cancels the other, which must stop rather than poll on
/// (and possibly save a second token) for the rest of its window.
void main() {
  test('a cancelled poll stops at its next tick and returns null', () async {
    final auth = PlexAuth(PlexClient.forTest(dio: Dio()));
    var ticks = 0;

    final token = await auth
        .pollForToken(
          const PlexPinResult(id: 1, code: 'ABCD'),
          interval: const Duration(milliseconds: 1),
          onTick: () => ticks++,
          isCancelled: () => true,
        )
        .timeout(const Duration(seconds: 2));

    expect(token, isNull);
    expect(ticks, 0, reason: 'cancelled before any request went out');
  });
}
