import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/storage/named_bookmark_store.dart';
import '../../core/theme/saga_theme.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/saga_sheet.dart';
import '../../shared/widgets/saga_toast.dart';
import 'player_service.dart';
import 'track_position_math.dart';

/// The one sheet for naming a bookmark — adding from the player, editing from
/// the player's bookmark list, editing from All Bookmarks.
///
/// Three near-identical copies existed and had already drifted: one labelled
/// the field "Title" and the others "Label", one disposed its controllers and
/// one didn't, and the player's copy jumped by seeking the bookmark's offset
/// into whichever file was playing. A change to how bookmarks are named now
/// has one place to land.
///
/// [onSave] receives the final label — never empty, an emptied field falls
/// back to [initialLabel] — and the note, null when blank. [onJumpTo], when
/// given, shows the Jump-to button; the sheet closes itself first, so the
/// callback runs against whatever is underneath. Cancel calls neither.
Future<void> showBookmarkEditSheet(
  BuildContext context, {
  required String title,
  required int positionMs,
  required String initialLabel,
  String? initialNote,
  required void Function(String label, String? note) onSave,
  VoidCallback? onJumpTo,
}) {
  final labelCtrl = TextEditingController(text: initialLabel);
  final noteCtrl = TextEditingController(text: initialNote ?? '');
  final bottomPad = MediaQuery.of(context).padding.bottom;

  return showSagaSheet<void>(context, (_) => StatefulBuilder(
    builder: (sheetCtx, _) {
      final keyboardInset = MediaQuery.of(sheetCtx).viewInsets.bottom;
      return Padding(
        padding: EdgeInsets.only(bottom: bottomPad + keyboardInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SagaSheetTitle(title,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(
                fmtDuration(Duration(milliseconds: positionMs)),
                style: TextStyle(color: SagaColors.fgSubtle, fontSize: 13),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TextField(
                controller: labelCtrl,
                style: TextStyle(color: SagaColors.fg),
                decoration: InputDecoration(
                  labelText: 'Label',
                  labelStyle: TextStyle(color: SagaColors.fgMuted),
                  enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: SagaColors.border)),
                  focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: SagaColors.accent)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                controller: noteCtrl,
                minLines: 1,
                maxLines: 3,
                style: TextStyle(color: SagaColors.fg),
                decoration: InputDecoration(
                  labelText: 'Note (optional)',
                  labelStyle: TextStyle(color: SagaColors.fgMuted),
                  enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: SagaColors.border)),
                  focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: SagaColors.accent)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  if (onJumpTo != null)
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetCtx);
                        onJumpTo();
                      },
                      icon: const Icon(Icons.play_arrow, size: 16),
                      label: const Text('Jump to'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: SagaColors.accent,
                        side: BorderSide(
                            color: SagaColors.accent.withValues(alpha: 0.5)),
                      ),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(sheetCtx),
                    child: Text('Cancel',
                        style: TextStyle(color: SagaColors.fgMuted)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      final label = labelCtrl.text.trim();
                      final note = noteCtrl.text.trim();
                      onSave(label.isEmpty ? initialLabel : label,
                          note.isEmpty ? null : note);
                      Navigator.pop(sheetCtx);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SagaColors.accent,
                      foregroundColor: SagaColors.bg,
                    ),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  )).whenComplete(() {
    // The sheet isn't awaited by every caller, so this is the only point at
    // which the two controllers are known to be finished with.
    labelCtrl.dispose();
    noteCtrl.dispose();
  });
}

void showBookmarksListSheet(
    BuildContext context, WidgetRef ref, String bookKey,
    {required AudioPlayerService service}) {
  showSagaSheet<void>(context, (_) => Consumer(
    builder: (ctx, innerRef, _) {
        final bookmarks = innerRef.watch(bookmarkNotifierProvider(bookKey));
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (ctx2, scrollController) => Column(
            children: [
              const SagaSheetHandle(),
              SagaSheetTitle('Bookmarks'),
              Expanded(
                child: bookmarks.isEmpty
                    ? Center(
                        child: Text('No bookmarks yet',
                            style: TextStyle(color: SagaColors.fgSubtle)))
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: bookmarks.length,
                        itemBuilder: (context, i) {
                          final bm = bookmarks[i];
                          return ListTile(
                            leading: Icon(Icons.bookmark,
                                color: SagaColors.accent),
                            title: Text(bm.label,
                                style: TextStyle(
                                    color: SagaColors.fg, fontSize: 14)),
                            subtitle: bm.note != null && bm.note!.isNotEmpty
                                ? Text(bm.note!,
                                    style: TextStyle(
                                        color: SagaColors.fgSubtle,
                                        fontSize: 11,
                                        fontStyle: FontStyle.italic),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis)
                                : null,
                            trailing: IconButton(
                              icon: Icon(Icons.delete_outline,
                                  color: SagaColors.fgSubtle),
                              onPressed: () {
                                innerRef
                                    .read(bookmarkNotifierProvider(bookKey)
                                        .notifier)
                                    .remove(bm.id);
                              },
                            ),
                            onTap: () => _showBookmarkSheet(
                                ctx, innerRef, bookKey, bm,
                                service: service),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    ),
    showHandle: false,
  );
}

void _showBookmarkSheet(BuildContext context, WidgetRef ref, String bookKey,
    NamedBookmark bm, {required AudioPlayerService service}) {
  // The shared sheet; [context] here is the bookmark LIST sheet's own
  // context, so the extra pop in onJumpTo closes that list too.
  showBookmarkEditSheet(
    context,
    title: 'Bookmark',
    positionMs: bm.positionMs,
    initialLabel: bm.label,
    initialNote: bm.note,
    onSave: (label, note) {
      ref
          .read(bookmarkNotifierProvider(bookKey).notifier)
          .update(bm.copyWith(label: label, note: note));
      ref.read(bookmarkRevisionProvider.notifier).state++;
    },
    onJumpTo: () {
      // A bookmark's position is an offset inside ONE file. Seeking it
      // straight into whatever file is playing sent multi-file jumps to
      // the wrong track — and the 10-second autosave then overwrote the
      // real place. Resolve the bookmark's own track first, like every
      // other jump site (BookStartPoint.atTrack).
      final tracks = service.currentTracks;
      final idx =
          tracks.indexWhere((t) => t.ratingKey == bm.trackRatingKey);
      if (idx < 0) {
        showSagaToast(
            context,
            'The file this bookmark points into is no '
            'longer part of the book.',
            isError: true);
        return;
      }
      service.seekAbsolute(Duration(
          milliseconds: absoluteFromTrack(
              [for (final t in tracks) t.durationMs], idx, bm.positionMs)));
      Navigator.pop(context); // close the bookmark list under the sheet
    },
  );
}
