import 'package:material_ui/material_ui.dart';

import '../../core/theme/saga_theme.dart';

/// 2.0's header tile: 38px, radius 10, 18px glyph. The tooltip is also the
/// screen-reader label, since the tile has no text of its own.
///
/// Used by the player's header and the book screen's, where the tiles sit on
/// the cover: the surface behind the glyph is what keeps it readable there.
class HeaderTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const HeaderTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Material(
        color: SagaColors.surface,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(icon, size: 18, color: SagaColors.fg),
          ),
        ),
      ),
    );
  }
}
