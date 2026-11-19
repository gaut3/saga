import 'package:material_ui/material_ui.dart';

import '../../core/theme/saga_theme.dart';

/// A row in a sheet that chooses between things of different kinds (where to
/// play, when to stop): an icon tile, a title, an optional second line. The
/// chosen row is marked three ways — filled tile, accent title, check — so
/// it is found without reading. Rows don't pad their sides; the sheet does.
class ChoiceRow extends StatelessWidget {
  final IconData? icon;
  final Widget? leading;
  final String title;
  final String? subtitle;
  final bool selected;

  /// Shown at the row's end when it isn't selected (a selected row shows
  /// its check there).
  final Widget? trailing;
  final VoidCallback onTap;

  const ChoiceRow({
    super.key,
    this.icon,
    this.leading,
    required this.title,
    this.subtitle,
    required this.selected,
    this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: selected ? SagaColors.accent : SagaColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: leading ??
                      Icon(icon,
                          size: 22,
                          color: selected
                              ? SagaColors.accentFg
                              : SagaColors.fgMuted),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color:
                              selected ? SagaColors.accentText : SagaColors.fg,
                          fontSize: 16,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                      if (subtitle != null)
                        Text(subtitle!,
                            style: TextStyle(
                                color: SagaColors.fgMuted, fontSize: 12)),
                    ],
                  ),
                ),
                if (selected)
                  Icon(Icons.check_rounded, color: SagaColors.accent, size: 20),
                if (!selected && trailing != null) trailing!,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
