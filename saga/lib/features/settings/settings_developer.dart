part of 'settings_screen.dart';

/// Settings › Developer options: tools for testing Saga, on beta and dev
/// builds only (sync design § Developer options). Unlocked from About.
///
/// Rules for everything on this page: nothing here writes a position
/// directly, and nothing shows a token or an unredacted address — a
/// screenshot of it can end up in a bug report.
class _DeveloperPage extends ConsumerStatefulWidget {
  const _DeveloperPage();

  @override
  ConsumerState<_DeveloperPage> createState() => _DeveloperPageState();
}

class _DeveloperPageState extends ConsumerState<_DeveloperPage> {
  List<SaveAuditEntry> _saves = SaveAuditStore.entries();
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // The live position and the newest saves, once a second.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _saves = SaveAuditStore.entries());
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  static String _clock(DateTime t) =>
      '${fmtTime(t)}:${t.second.toString().padLeft(2, '0')}';

  /// How far the live position is from the saved one: what a kill right now
  /// would cost.
  String _liveGap() {
    final player = ref.read(playerServiceProvider);
    final book = player.currentBookRatingKey;
    if (book == null) return 'No book loaded';
    final live = player.absolutePositionMs;
    final saved = BookmarkStore.load(book);
    if (saved == null) return 'Now ${fmtBookPositionMs(live)} · not saved yet';
    final ago = DateTime.now().difference(saved.savedAt).inSeconds;
    final gapS = ((live - saved.absolutePositionMs) / 1000).round();
    return 'Now ${fmtBookPositionMs(live)} · saved '
        '${fmtBookPositionMs(saved.absolutePositionMs)}, ${ago}s ago '
        '(${gapS >= 0 ? '+' : ''}${gapS}s)';
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(sagaThemeVariantProvider);
    return _SettingsPage(
      title: 'Developer options',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(
              'For testing Saga. Only beta and dev builds have this page; a '
              'release never shows or reads it.',
              style: TextStyle(color: SagaColors.fgMuted, fontSize: 13)),
        ),
        _SectionHeader('Position saves'),
        Material(
          color: SagaColors.surface,
          child: ListTile(
            leading: Icon(Icons.my_location_outlined, color: SagaColors.accent),
            title: Text(_liveGap(),
                style: TextStyle(color: SagaColors.fg, fontSize: 14)),
            subtitle: Text(
                'The last ${SaveAuditStore.maxEntries} saves below, newest first. '
                'Held means the Plex report waited for playback to pass the '
                'loaded place.',
                style: TextStyle(color: SagaColors.fgSubtle, fontSize: 12)),
          ),
        ),
        if (_saves.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
                'No saves recorded yet. They are recorded while developer '
                'options are on.',
                style: TextStyle(color: SagaColors.fgSubtle, fontSize: 12)),
          )
        else
          Material(
            color: SagaColors.surface,
            child: Column(
              children: [
                for (final s in _saves)
                  ListTile(
                    dense: true,
                    leading: Icon(
                        s.reported
                            ? Icons.cloud_done_outlined
                            : Icons.cloud_off_outlined,
                        color: s.reported
                            ? SagaColors.accent
                            : SagaColors.fgSubtle),
                    title: Text(
                        '${_clock(s.at)}  ·  ${fmtBookPositionMs(s.positionMs)}',
                        style: TextStyle(
                            color: SagaColors.fg,
                            fontSize: 14,
                            fontFeatures: const [FontFeature.tabularFigures()])),
                    subtitle: Text(
                        '${s.trigger} · book ${s.bookKey} · '
                        '${s.reported ? 'sent to Plex' : s.heldUntilMs == null ? 'held' : 'held until ${fmtBookPositionMs(s.heldUntilMs!)}'}',
                        style: TextStyle(
                            color: SagaColors.fgSubtle, fontSize: 12)),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 24),
        _SettingsTile(
          icon: Icons.visibility_off_outlined,
          title: 'Hide developer options',
          subtitle: 'Tap the version in About seven times to bring them back',
          onTap: () async {
            await SettingsStore.setDeveloperOptions(false);
            if (!mounted) return;
            Navigator.of(this.context).pop();
          },
        ),
      ],
    );
  }
}
