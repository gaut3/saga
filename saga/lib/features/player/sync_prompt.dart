import 'package:material_ui/material_ui.dart';

import '../../core/theme/saga_theme.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/saga_sheet.dart';
import '../../shared/widgets/saga_toast.dart';

/// Sync rule 9, apply: the place was taken from Plex. Tapping the toast
/// goes back (the player's Undo does the same).
void showSyncAppliedToast(BuildContext context,
    {required int serverMs, required VoidCallback undo}) {
  showSagaToast(
    context,
    'Picked up at ${fmtBookPositionMs(serverMs)} from another device · '
    'Tap to undo',
    duration: const Duration(seconds: 6),
    onTap: undo,
  );
}

/// Sync rule 9, ask: Plex's place is newer but further back. The finished
/// panel's two-button shape. True takes Plex's place, false does what the
/// listener asked for (stays, or starts over); dismissing it returns null,
/// which does the same.
///
/// A [finished] book (rule 8) is the case of finishing it here and then
/// listening again elsewhere: the newer place is offered, never taken on its
/// own, since a sync never clears a finish. [startsOver] is "Listen again",
/// whose own choice is the start, so the second button says so.
Future<bool?> showSyncAskSheet(BuildContext context,
    {required int serverMs,
    required int localMs,
    bool finished = false,
    bool startsOver = false}) {
  final stayLabel =
      startsOver ? 'Start over' : 'Stay at ${fmtBookPositionMs(localMs)}';
  final bottomPad = MediaQuery.of(context).padding.bottom;
  return showSagaSheet<bool>(
    context,
    (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + bottomPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SagaSheetTitle(
              finished
                  ? 'Listened to on another device'
                  : 'Another device is further back',
              padding: const EdgeInsets.only(bottom: 6)),
          Text(
              finished
                  ? 'You finished this book here. Since then, another device '
                      'has listened to it up to ${fmtBookPositionMs(serverMs)}.'
                  : 'Plex was told about ${fmtBookPositionMs(serverMs)} more '
                      'recently than this phone saved '
                      '${fmtBookPositionMs(localMs)}. Which place do you want?',
              style: TextStyle(color: SagaColors.fgMuted, fontSize: 14)),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: SagaColors.accent,
                foregroundColor: SagaColors.accentFg,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(
                  'Resume synced position · ${fmtBookPositionMs(serverMs)}'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(ctx, false),
              style: OutlinedButton.styleFrom(
                foregroundColor: SagaColors.fg,
                side: BorderSide(
                    color: SagaColors.accent.withValues(alpha: 0.4)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(stayLabel),
            ),
          ),
        ],
      ),
    ),
    scrollable: false,
  );
}

/// Plex's place, offered after audio started here without it (a downloaded
/// book never waits; a late answer). A prompt rather than a toast, which is
/// easy to miss while listening. True jumps there; anything else keeps
/// playing where it is.
Future<bool?> showSyncOfferSheet(BuildContext context,
    {required int serverMs, required int hereMs}) {
  final ahead = serverMs > hereMs;
  final bottomPad = MediaQuery.of(context).padding.bottom;
  return showSagaSheet<bool>(
    context,
    (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + bottomPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SagaSheetTitle(
              ahead
                  ? 'Another device is further ahead'
                  : 'Another device is further back',
              padding: const EdgeInsets.only(bottom: 6)),
          Text(
              'Plex has ${fmtBookPositionMs(serverMs)} from another device, '
              'newer than where this phone started. Jump there?',
              style: TextStyle(color: SagaColors.fgMuted, fontSize: 14)),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: SagaColors.accent,
                foregroundColor: SagaColors.accentFg,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: Text('Jump to ${fmtBookPositionMs(serverMs)}'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(ctx, false),
              style: OutlinedButton.styleFrom(
                foregroundColor: SagaColors.fg,
                side: BorderSide(
                    color: SagaColors.accent.withValues(alpha: 0.4)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Keep listening here'),
            ),
          ),
        ],
      ),
    ),
    scrollable: false,
  );
}
