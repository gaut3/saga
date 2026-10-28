import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/diagnostics/app_log.dart';
import '../../core/plex/models/plex_track.dart';
import '../../core/providers.dart';
import '../../core/stats/listening_sessions.dart';
import '../../core/storage/playback_log_store.dart';
import '../../core/theme/saga_theme.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/saga_mark.dart';
import '../../shared/widgets/saga_toast.dart';
import 'book_launch.dart';
import 'open_player.dart';
import 'player_provider.dart';
import 'session_place.dart';
import 'session_preview.dart';

/// One listening session — when, where in the book it ran, how long — with
/// the two things a listener does with it: **preview** (the mark: ~30 s
/// around where it ended, nothing saved) and **resume** (start the book
/// there). The one row for the player's Sessions sheet, book detail's (the
/// same sheet) and History's per-book panel.
///
/// Both act on where the session *ended*: that's the last thing heard — the
/// spot to check after falling asleep. A session the log never saw close
/// (app killed mid-listen) acts on its start instead.
class SessionRow extends ConsumerWidget {
  final String bookKey;
  final ListeningSession session;

  /// False where the surrounding list already names the day (History).
  final bool showDay;

  /// True when the row sits in a sheet: resume closes it before starting.
  final bool inSheet;

  /// True when that sheet is over the full player: resume starts the book in
  /// place, instead of pushing a second player on top of the first.
  final bool overPlayer;

  const SessionRow({
    super.key,
    required this.bookKey,
    required this.session,
    this.showDay = true,
    this.inSheet = false,
    this.overPlayer = false,
  });

  AudioLogEvent get _target => session.pause ?? session.play;

  String get _previewId =>
      '$bookKey:${session.play.timestamp.millisecondsSinceEpoch}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final start = placeOfEvent(bookKey, session.play);
    final end =
        session.pause == null ? null : placeOfEvent(bookKey, session.pause!);
    final chapter = (end ?? start)?.chapter;

    final clock = session.pause == null
        ? fmtTime(session.play.timestamp)
        : '${fmtTime(session.play.timestamp)}–${fmtTime(session.pause!.timestamp)}';
    final when =
        showDay ? '${relativeDayLabel(session.play.timestamp)} · $clock' : clock;

    final where = [
      if (start != null && end != null)
        '${fmtBookPositionMs(start.absoluteMs)} → '
            '${fmtBookPositionMs(end.absoluteMs)}'
      else if (start != null)
        'from ${fmtBookPositionMs(start.absoluteMs)}',
      if (session.duration != null)
        fmtListenedMs(session.duration!.inMilliseconds),
    ].join('  ·  ');

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          ValueListenableBuilder<String?>(
            valueListenable: SessionPreview.instance.active,
            builder: (context, active, _) {
              final previewing = active == _previewId;
              // Labelled like Resume on the other side: the mark alone read
              // as "play the book", which is Resume's job.
              return Semantics(
                button: true,
                label: previewing ? 'Stop preview' : 'Preview this spot',
                excludeSemantics: true,
                child: InkWell(
                  onTap: () => _preview(context, ref),
                  borderRadius: BorderRadius.circular(8),
                  // Fixed width: "Preview" and "Stop" differ, and sized to its
                  // label the control shifted sideways when the label swapped.
                  child: Container(
                    width: 56,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: SagaColors.accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: AnimatedSagaMark(
                            size: 20,
                            state: previewing
                                ? SagaMarkState.playing
                                : SagaMarkState.paused,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          previewing ? 'Stop' : 'Preview',
                          style: TextStyle(
                              color: SagaColors.accentText,
                              fontSize: 11,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  when,
                  style: TextStyle(
                      color: SagaColors.fg,
                      fontSize: 14,
                      fontWeight: FontWeight.w600),
                ),
                if (where.isNotEmpty)
                  Text(
                    where,
                    style:
                        TextStyle(color: SagaColors.fgSubtle, fontSize: 12.5),
                  ),
                if (chapter != null)
                  Text(
                    chapter,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(color: SagaColors.fgSubtle, fontSize: 12.5),
                  ),
              ],
            ),
          ),
          // Icon over a small label, not a text button: the word beside the
          // text took enough width to wrap the duration onto its own line,
          // and an icon alone didn't say what it does.
          Semantics(
            button: true,
            label: 'Resume from here',
            excludeSemantics: true,
            child: InkWell(
              onTap: () => _resume(context, ref),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.play_circle_outline_rounded,
                        size: 26, color: SagaColors.accent),
                    const SizedBox(height: 2),
                    Text(
                      'Resume',
                      style: TextStyle(
                          color: SagaColors.accentText,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The target event's track, or null (after saying why) when the book no
  /// longer has it or the track list can't be loaded.
  Future<({List<PlexTrack> tracks, PlexTrack track})?> _targetTrack(
      BuildContext context, WidgetRef ref) async {
    try {
      final tracks = await ref.read(tracksProvider(bookKey).future);
      final track = tracks
          .where((t) => t.ratingKey == _target.trackRatingKey)
          .firstOrNull;
      if (track == null) {
        if (context.mounted) {
          showSagaToast(
              context,
              'The file this session points into is no longer '
              'part of the book.',
              isError: true);
        }
        return null;
      }
      return (tracks: tracks, track: track);
    } catch (e) {
      AppLog.log('playback', 'session track lookup failed: $e');
      if (context.mounted) {
        showSagaToast(context,
            'Couldn\'t load this book — is the server reachable?',
            isError: true);
      }
      return null;
    }
  }

  Future<void> _preview(BuildContext context, WidgetRef ref) async {
    // Stopping needs no track lookup — and must work offline.
    if (SessionPreview.instance.active.value == _previewId) {
      await SessionPreview.instance.stop();
      return;
    }
    final found = await _targetTrack(context, ref);
    if (found == null) return;
    final ok = await SessionPreview.instance.toggle(
      id: _previewId,
      track: found.track,
      positionMs: _target.positionMs,
      main: ref.read(playerServiceProvider),
    );
    if (!ok && context.mounted) {
      showSagaToast(context, 'Couldn\'t play a preview of this spot.',
          isError: true);
    }
  }

  Future<void> _resume(BuildContext context, WidgetRef ref) async {
    await SessionPreview.instance.stop();
    if (!context.mounted) return;
    final found = await _targetTrack(context, ref);
    if (found == null || !context.mounted) return;
    final from = BookStartPoint.atTrack(_target.trackRatingKey,
        positionMs: _target.positionMs);
    final service = ref.read(playerServiceProvider);

    // A sheet closes *first*, and everything after runs on the root
    // navigator's context, which outlives it. Over the player the reason is
    // that startBook doesn't return until playback ends (it awaits play(),
    // whose future completes on pause/stop) — waiting on it kept the sheet
    // up for the whole listen. From a tab, the player would otherwise be
    // pushed over the sheet and back would land on it again.
    final rootContext = Navigator.of(context, rootNavigator: true).context;
    if (inSheet) Navigator.of(context).pop();

    if (overPlayer) {
      // startBook never throws — it logs and returns false.
      final started = await startBook(
          service: service,
          bookRatingKey: bookKey,
          tracks: found.tracks,
          from: from);
      if (!started && rootContext.mounted) {
        showSagaToast(rootContext,
            'Couldn\'t load this book — is the server reachable?',
            isError: true);
      }
      return;
    }
    // Pushes the player immediately and says why itself on failure.
    await openPlayerAndStart(
      context: rootContext,
      service: service,
      bookRatingKey: bookKey,
      loadTracks: () async => found.tracks,
      from: from,
    );
  }
}
