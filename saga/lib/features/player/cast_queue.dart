import '../../core/cast/cast_service.dart';
import '../../core/plex/models/plex_track.dart';
import '../../core/plex/plex_client.dart';

/// What a TV needs to play [tracks]: one queue item per file, with the URLs
/// [PlexClient.buildCastMedia] makes, and the cover (empty when the URL
/// would cost the account token). Null without a reachable server.
///
/// In a file of its own so the audio handler, which feeds the platform media
/// session, never builds a token-bearing URL itself (`media_browse_test`).
Future<({List<CastQueueItem> items, String artwork})?> castQueueFor(
    List<PlexTrack> tracks) async {
  if (tracks.isEmpty) return null;
  final media = await PlexClient.instance.buildCastMedia(
    partKeys: [for (final t in tracks) t.partKey],
    thumbPath: tracks.first.thumbPath,
  );
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
