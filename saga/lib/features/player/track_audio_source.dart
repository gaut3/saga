import 'package:just_audio/just_audio.dart';

import '../../core/plex/models/plex_track.dart';
import '../../core/plex/plex_client.dart';

/// The audio source for one track: the downloaded file when there is one,
/// else the Plex stream with the token in a *header* (never the URL — see
/// CLAUDE.md § Security). Shared by the main player and the session preview
/// so the two can't drift on how they reach the audio.
UriAudioSource audioSourceForTrack(PlexTrack t) {
  final localPath = PlexClient.localTrackPath(t);
  if (localPath != null) {
    return AudioSource.file(localPath, tag: t.ratingKey);
  }
  final streamUrl = PlexClient.instance.buildStreamUrl(t.partKey);
  if (streamUrl == null) throw StateError('No Plex server configured');
  return AudioSource.uri(
    Uri.parse(streamUrl),
    headers: PlexClient.instance.authHeaders,
    tag: t.ratingKey,
  );
}
