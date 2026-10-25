import 'package:flutter/material.dart';

import '../../core/stats/listening_sessions.dart';
import '../../core/storage/playback_log_store.dart';
import '../../core/theme/saga_theme.dart';
import '../../shared/widgets/saga_sheet.dart';
import 'session_preview.dart';
import 'session_row.dart';

/// A book's listening sessions, newest first, each with preview and resume.
///
/// [overPlayer]: opened from the full player (see [SessionRow.overPlayer]).
void showSessionsSheet(BuildContext context, String bookKey,
    {bool overPlayer = false}) {
  // Shared pairing rule (core/stats). The hand-rolled loop this replaces
  // required play and pause to be *adjacent in the raw log*, but skip and
  // sleep-timer events land in the same list — so a session with a sleep
  // timer set inside it showed no duration here while History showed one.
  final sessions = pairListeningSessions(PlaybackLogStore.getLog(bookKey))
    ..sort((a, b) => b.play.timestamp.compareTo(a.play.timestamp));
  // From a tab the sheet mounts under the nav bar and mini player, which the
  // caller's padding already accounts for (extendBody). Over the player
  // there's nothing beneath it.
  final bottomInset = MediaQuery.of(context).padding.bottom;

  showSagaSheet<void>(
    context,
    (_) => _SessionsSheet(
      bookKey: bookKey,
      sessions: sessions,
      overPlayer: overPlayer,
      bottomInset: bottomInset,
    ),
    showHandle: false,
  );
}

class _SessionsSheet extends StatefulWidget {
  final String bookKey;
  final List<ListeningSession> sessions;
  final bool overPlayer;
  final double bottomInset;

  const _SessionsSheet({
    required this.bookKey,
    required this.sessions,
    required this.overPlayer,
    required this.bottomInset,
  });

  @override
  State<_SessionsSheet> createState() => _SessionsSheetState();
}

class _SessionsSheetState extends State<_SessionsSheet> {
  @override
  void dispose() {
    // A preview is for this list; it doesn't outlive it.
    SessionPreview.instance.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sessions = widget.sessions;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      builder: (_, ctrl) => Column(
        children: [
          const SagaSheetHandle(),
          SagaSheetTitle('Sessions',
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0)),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 4),
            child: Text(
              'Tap the mark to hear where a session ended. '
              'Your place only moves when you tap Resume.',
              style: TextStyle(color: SagaColors.fgSubtle, fontSize: 12.5),
            ),
          ),
          Expanded(
            child: sessions.isEmpty
                ? Center(
                    child: Text('No sessions yet',
                        style: TextStyle(color: SagaColors.fgMuted)),
                  )
                : ListView.builder(
                    controller: ctrl,
                    padding: EdgeInsets.fromLTRB(
                        16, 0, 16, 24 + widget.bottomInset),
                    itemCount: sessions.length,
                    itemBuilder: (_, i) => SessionRow(
                      bookKey: widget.bookKey,
                      session: sessions[i],
                      inSheet: true,
                      overPlayer: widget.overPlayer,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
