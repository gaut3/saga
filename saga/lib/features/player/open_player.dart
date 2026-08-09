import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/diagnostics/app_log.dart';
import '../../core/plex/models/plex_track.dart';
import '../../shared/widgets/saga_toast.dart';
import 'book_launch.dart';
import 'player_screen.dart';
import 'player_service.dart';

/// Pushes the full-screen player and starts a book through [startBook] —
/// and, the part every call site got wrong on its own, takes the player back
/// down when the launch fails.
///
/// The route is pushed *before* [loadTracks] is awaited, on purpose: the
/// player derives everything it shows from the service's streams, so opening
/// instantly and letting the book arrive is what makes a tap feel immediate
/// (see the note in [PlayerScreen.build]). The cost of that ordering is the
/// failure case: a launch that failed used to leave a full-screen player
/// showing whatever book was loaded *before* — working controls and all —
/// behind at best a 4-second toast saying why. Five screens carried their own
/// copy of this sequence; none of them popped.
///
/// [loadTracks] runs inside so its failure is handled the same way; callers
/// that already hold the list pass `() async => tracks`. Callers with a more
/// specific failure to report (a bookmark whose file is gone) should check
/// and say it *before* calling.
Future<bool> openPlayerAndStart({
  required BuildContext context,
  required AudioPlayerService service,
  required String bookRatingKey,
  required Future<List<PlexTrack>> Function() loadTracks,
  required BookStartPoint from,
  LaunchPlayback playback = LaunchPlayback.start,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = MaterialPageRoute<void>(builder: (_) => const PlayerScreen());
  unawaited(navigator.push(route));

  var tracks = const <PlexTrack>[];
  try {
    tracks = await loadTracks();
  } catch (e) {
    AppLog.log('playback', 'open player: track load failed: $e');
  }

  // startBook never throws — it logs and returns false.
  final started = tracks.isNotEmpty &&
      await startBook(
        service: service,
        bookRatingKey: bookRatingKey,
        tracks: tracks,
        from: from,
        playback: playback,
      );

  if (!started) {
    // Popped if it's still on top, removed quietly if something else has
    // been pushed over it in the meantime.
    if (route.isCurrent) {
      navigator.pop();
    } else if (route.isActive) {
      navigator.removeRoute(route);
    }
    if (context.mounted) {
      showSagaToast(
          context, 'Couldn\'t load this book — is the server reachable?',
          isError: true);
    }
  }
  return started;
}
