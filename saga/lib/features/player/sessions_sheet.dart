import 'package:flutter/material.dart';

import '../../core/stats/listening_sessions.dart';
import '../../core/storage/playback_log_store.dart';
import '../../core/theme/saga_theme.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/saga_sheet.dart';

void showSessionsSheet(BuildContext context, String bookKey) {
  // Shared pairing rule (core/stats). The hand-rolled loop this replaces
  // required play and pause to be *adjacent in the raw log*, but skip and
  // sleep-timer events land in the same list — so a session with a sleep
  // timer set inside it showed no duration here while History showed one.
  final sessions = [
    for (final s in pairListeningSessions(PlaybackLogStore.getLog(bookKey)))
      (start: s.play.timestamp, duration: s.duration)
  ]..sort((a, b) => b.start.compareTo(a.start));

  showSagaSheet<void>(context, (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      builder: (_, ctrl) => Column(
        children: [
          const SagaSheetHandle(),
          SagaSheetTitle('Sessions',
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8)),
          Expanded(
            child: ListView.builder(
              controller: ctrl,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              itemCount: sessions.length,
              itemBuilder: (_, i) {
                final s = sessions[i];
                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: SagaColors.accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.play_arrow,
                            color: SagaColors.accent, size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Shared formatters: the local pair these
                            // replace printed a 12-hour clock where the rest
                            // of the app prints 24-hour, and dated
                            // "Yesterday" with a `Duration`, which stops
                            // matching when the clocks change.
                            Text(
                              relativeDayLabel(s.start),
                              style: TextStyle(
                                  color: SagaColors.fg,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600),
                            ),
                            Text(
                              fmtTime(s.start) +
                                  (s.duration != null
                                      ? '  ·  ${fmtDurationMs(s.duration!.inMilliseconds)}'
                                      : ''),
                              style: TextStyle(
                                  color: SagaColors.fgSubtle, fontSize: 12.5),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
    showHandle: false,
  );
}
