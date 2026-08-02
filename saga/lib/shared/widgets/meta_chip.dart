import 'package:flutter/material.dart';

import '../../core/theme/saga_theme.dart';

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
