import 'package:flutter/material.dart';

import '../../core/storage/custom_collection_store.dart';
import '../../core/theme/saga_theme.dart';
import '../../shared/widgets/saga_sheet.dart';

/// The one sheet for picking a custom collection — adding a Browse selection
/// to one, or toggling a single book's membership from its detail screen.
///
/// The two copies this replaces had already drifted: different list-height
/// caps, one guarded its post-await ref use and one didn't, and they sourced
/// cover thumbnails differently. Behaviour on tap belongs to the caller via
/// [onPick]; the sheet closes itself once that completes.
///
/// [isSelected] marks collections with a check — the detail screen uses it to
/// show current membership.
Future<void> showCollectionPickerSheet(
  BuildContext context, {
  required String title,
  bool Function(CustomCollection col)? isSelected,
  required Future<void> Function(CustomCollection col) onPick,
}) {
  final collections = CustomCollectionStore.getAll();
  // Captured from the tab-navigator context, where padding.bottom already
  // includes the full Saga nav bar + mini player height.
  final bottomPad = MediaQuery.of(context).padding.bottom;

  return showSagaSheet<void>(context, (ctx) => Padding(
        padding: EdgeInsets.only(bottom: bottomPad),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SagaSheetTitle(title,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8)),
            if (collections.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                    'No collections yet — create one in the Collections tab.',
                    style: TextStyle(color: SagaColors.fgMuted)),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  // The bottom padding above eats into the sheet's height, so
                  // the cap subtracts it — without this the list could push
                  // the title off the top on small screens.
                  maxHeight:
                      MediaQuery.of(ctx).size.height * 0.55 - bottomPad,
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    ...collections.map((col) {
                      final selected = isSelected?.call(col) ?? false;
                      final count = col.bookRatingKeys.length;
                      return ListTile(
                        leading: Icon(
                          selected
                              ? Icons.check_circle
                              : Icons.folder_outlined,
                          color: selected
                              ? SagaColors.accent
                              : SagaColors.fgMuted,
                        ),
                        title: Text(col.name,
                            style: TextStyle(color: SagaColors.fg)),
                        subtitle: Text(
                            '$count ${count == 1 ? 'book' : 'books'}',
                            style: TextStyle(
                                color: SagaColors.fgSubtle, fontSize: 12)),
                        onTap: () async {
                          await onPick(col);
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                      );
                    }),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
          ],
        ),
      ));
}
