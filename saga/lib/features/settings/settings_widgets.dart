part of 'settings_screen.dart';

/// The pinned header every Settings screen uses: transparent, fading the
/// page out beneath it. The index passes its 22/bold title; pages a 20/w700
/// one, with the back arrow the route gives them.
SliverAppBar _settingsAppBar(Widget title) => SliverAppBar(
      pinned: true,
      backgroundColor: Colors.transparent,
      foregroundColor: SagaColors.fg,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [SagaColors.bg, SagaColors.bg.withValues(alpha: 0.0)],
            stops: const [0.6, 1.0],
          ),
        ),
      ),
      title: title,
    );

/// A page pushed from the Settings index (handoff 13b–13g): the header with
/// a back arrow, then [children] in one painted layer, as the index.
class _SettingsPage extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SettingsPage({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SagaColors.bg,
      body: CustomScrollView(
        slivers: [
          _settingsAppBar(Text(title,
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20))),
          SliverToBoxAdapter(
            child: RepaintBoundary(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  ...children,
                  SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: SagaColors.fgSubtle,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color? iconColor;
  final VoidCallback onTap;

  const _SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: SagaColors.surface,
      child: ListTile(
        leading: Icon(icon, color: iconColor ?? SagaColors.accent),
        title: Text(title, style: TextStyle(color: SagaColors.fg)),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: SagaColors.fgSubtle, fontSize: 12),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Icon(Icons.chevron_right, color: SagaColors.fgSubtle),
        onTap: onTap,
      ),
    );
  }
}

class _SegmentedTile extends StatelessWidget {
  final IconData icon;
  // Material has no unnumbered forward-arc icon, so "skip forward" mirrors
  // Icons.replay_rounded — same trick as the player's _SkipIntervalIcon.
  final bool flipIcon;
  final String title;
  final List<String> options;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const _SegmentedTile({
    required this.icon,
    this.flipIcon = false,
    required this.title,
    required this.options,
    required this.selectedIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: SagaColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Transform.flip(
            flipX: flipIcon,
            child: Icon(icon, color: SagaColors.accent, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(title,
                style: TextStyle(color: SagaColors.fg, fontSize: 16)),
          ),
          ToggleButtons(
            isSelected: List.generate(
                options.length, (i) => i == selectedIndex),
            onPressed: onChanged,
            borderColor: SagaColors.border,
            selectedBorderColor: SagaColors.accent,
            selectedColor: SagaColors.accentFg,
            fillColor: SagaColors.accent,
            color: SagaColors.fgMuted,
            borderRadius: BorderRadius.circular(8),
            constraints:
                const BoxConstraints(minWidth: 44, minHeight: 32),
            children: options
                .map((o) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text(o, style: const TextStyle(fontSize: 12)),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: SagaColors.surface,
      child: SwitchListTile(
        secondary: Icon(icon, color: SagaColors.accent),
        title: Text(title, style: TextStyle(color: SagaColors.fg)),
        subtitle: subtitle != null
            ? Text(subtitle!,
                style: TextStyle(color: SagaColors.fgSubtle, fontSize: 12))
            : null,
        value: value,
        onChanged: onChanged,
        // On: amber. Off: Saga-themed instead of Material's white/grey default.
        activeThumbColor: SagaColors.accent,
        inactiveThumbColor: SagaColors.fgMuted,
        inactiveTrackColor: SagaColors.surfaceAlt,
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.transparent
              : SagaColors.border,
        ),
      ),
    );
  }
}

