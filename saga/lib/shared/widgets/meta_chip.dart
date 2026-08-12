import 'package:flutter/material.dart';

import '../../core/plex/models/plex_book.dart';
import '../../core/theme/saga_theme.dart';
import '../../core/utils/format.dart';

/// A small icon + label pill for a single piece of book metadata (year,
/// duration, chapter count, studio…).
///
/// Shared so the book detail screen and the player's flipped cover render the
/// same chip — they show the same facts and must not drift apart.
class MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const MetaChip(this.icon, this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: SagaColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: SagaColors.fgSubtle),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: SagaColors.fgMuted, fontSize: 12)),
        ],
      ),
    );
  }
}

/// The facts both chip rows agree on: year · length · chapters · studio ·
/// first two genres. The detail screen and the player's flipped cover each
/// append their own extras after these; the shared list is what keeps the
/// facts themselves from drifting.
List<Widget> bookMetaChips(PlexBook book,
        {required int? lengthMs, required int? chapterCount}) =>
    [
      if (book.year != null)
        MetaChip(Icons.calendar_today_outlined, '${book.year}'),
      if (lengthMs != null)
        MetaChip(Icons.schedule_outlined, fmtDurationMs(lengthMs)),
      if (chapterCount != null)
        MetaChip(Icons.format_list_numbered_outlined,
            chapterCount == 1 ? '1 chapter' : '$chapterCount chapters'),
      if (book.studio != null) MetaChip(Icons.business_outlined, book.studio!),
      for (final g in book.genres.take(2))
        MetaChip(Icons.local_offer_outlined, g),
    ];
