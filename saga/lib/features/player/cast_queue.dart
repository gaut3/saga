import '../../core/cast/cast_service.dart';
import '../../core/diagnostics/app_log.dart';
import '../../core/plex/models/plex_track.dart';
import '../../core/plex/plex_client.dart';
import '../../core/plex/plex_server.dart';

/// What a TV needs to play [tracks]: one queue item per file, with the URLs
/// [PlexClient.buildCastMedia] makes, and the cover (empty when the URL
/// would cost the account token). Null without a reachable server.
///
/// In a file of its own so the audio handler, which feeds the platform media
/// session, never builds a token-bearing URL itself (`media_browse_test`).
Future<({List<CastQueueItem> items, String artwork})?> castQueueFor(
    List<PlexTrack> tracks) async {
  if (tracks.isEmpty) return null;
  Future<({List<String> streamUrls, String? artUrl})?> build() =>
      PlexClient.instance.buildCastMedia(
        partKeys: [for (final t in tracks) t.partKey],
        thumbPath: tracks.first.thumbPath,
      );
  var media = await build();
  if (media == null) {
    // The saved address didn't answer. A downloaded book plays without the
    // server, so nothing else may have noticed since it was chosen — often
    // away from home, and unreachable from inside it (#24). Choose again.
    AppLog.log('server', 'cast: saved address unreachable — re-checking');
    try {
      if (await PlexServerDiscovery(PlexClient.instance).rediscover()) {
        media = await build();
      }
    } catch (e) {
      AppLog.log('server', 'cast: re-check failed: $e');
    }
  }
  if (media == null) return null;
  return (
    items: [
      for (var i = 0; i < tracks.length; i++)
        (
          url: media.streamUrls[i],
          contentType: castContentTypeFor(tracks[i].partFile),
          durationMs: tracks[i].durationMs,
          trackTitle: tracks[i].title,
        ),
    ],
    artwork: media.artUrl ?? '',
  );
}
