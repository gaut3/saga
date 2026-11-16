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
/// panel's two-button shape. True takes Plex's place, false stays; dismissing
/// it returns null, which stays too.
Future<bool?> showSyncAskSheet(BuildContext context,
    {required int serverMs, required int localMs}) {
  final bottomPad = MediaQuery.of(context).padding.bottom;
  return showSagaSheet<bool>(
    context,
    (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + bottomPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SagaSheetTitle('Another device is further back',
              padding: const EdgeInsets.only(bottom: 6)),
          Text(
              'Plex was told about ${fmtBookPositionMs(serverMs)} more '
              'recently than this phone saved ${fmtBookPositionMs(localMs)}. '
              'Which place do you want?',
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
              child: Text('Stay at ${fmtBookPositionMs(localMs)}'),
            ),
          ),
        ],
      ),
    ),
    scrollable: false,
  );
}
