part of 'settings_screen.dart';

/// Settings › Playback (handoff 13b).
class _PlaybackPage extends ConsumerStatefulWidget {
  const _PlaybackPage();

  @override
  ConsumerState<_PlaybackPage> createState() => _PlaybackPageState();
}

class _PlaybackPageState extends ConsumerState<_PlaybackPage> {
  static const _skipOptions = [15, 30, 45, 60];
  static const _boostOptions = [0, 3, 6, 9];
  static String _sleepTimerLabel(int minutes) {
    if (minutes == 0) return 'Off';
    if (minutes == -1) return 'End of chapter';
    return '$minutes min';
  }

  late int _skipForward;
  late int _skipBackward;
  late double _defaultSpeed;
  late int _volumeBoost;
  late bool _skipSilence;
  late bool _autoRewind;
  late bool _autoPlayNextBook;
  late bool _resumeAfterInterruption;
  late bool _chapterScrub;
  late bool _mediaButtonsSkip;
  late int _markMotion;
  late int _animationSyncDelay;
  late int _defaultSleepTimer;

  @override
  void initState() {
    super.initState();
    _skipForward = SettingsStore.skipForwardSeconds;
    _skipBackward = SettingsStore.skipBackwardSeconds;
    _defaultSpeed = SettingsStore.defaultSpeed;
    _volumeBoost = SettingsStore.volumeBoostDb;
    _skipSilence = SettingsStore.skipSilence;
    _autoRewind = SettingsStore.autoRewindEnabled;
    _autoPlayNextBook = SettingsStore.autoPlayNextBook;
    _resumeAfterInterruption = SettingsStore.resumeAfterInterruption;
    _chapterScrub = SettingsStore.chapterScrub;
    _mediaButtonsSkip = SettingsStore.mediaButtonsSkip;
    _markMotion = SettingsStore.markMotionIndex;
    _animationSyncDelay = SettingsStore.animationSyncDelayMs;
    _defaultSleepTimer = SettingsStore.defaultSleepTimerMinutes;
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(sagaThemeVariantProvider);
    return _SettingsPage(
      title: 'Playback',
      children: [
          _SegmentedTile(
            icon: Icons.replay_rounded,
            title: 'Skip back',
            options: _skipOptions.map((s) => '${s}s').toList(),
            selectedIndex:
                _skipOptions.indexOf(_skipBackward).clamp(0, 3),
            onChanged: (i) async {
              final v = _skipOptions[i];
              await SettingsStore.setSkipBackward(v);
              if (!mounted) return;
              setState(() => _skipBackward = v);
            },
          ),
          _SegmentedTile(
            icon: Icons.replay_rounded,
            flipIcon: true,
            title: 'Skip forward',
            options: _skipOptions.map((s) => '${s}s').toList(),
            selectedIndex:
                _skipOptions.indexOf(_skipForward).clamp(0, 3),
            onChanged: (i) async {
              final v = _skipOptions[i];
              await SettingsStore.setSkipForward(v);
              if (!mounted) return;
              setState(() => _skipForward = v);
            },
          ),
          _SettingsTile(
            icon: Icons.speed,
            title: 'Default speed',
            subtitle: '${fmtSpeed(_defaultSpeed)}×',
            onTap: () => showSpeedSheet(
              context,
              title: 'Default speed',
              speed: _defaultSpeed,
              onChanged: (v) async {
                await SettingsStore.setDefaultSpeed(v);
                if (!mounted) return;
                setState(() => _defaultSpeed = v);
                // Apply immediately if a player is active — but only to a
                // book riding the default. A book with its own saved speed
                // keeps it: applying the new default anyway audibly
                // changed the live session while the stored per-book
                // speed survived, so the next load snapped back.
                final player = ref.read(playerServiceProvider);
                final bookKey = player.currentBookRatingKey;
                if (bookKey == null ||
                    !SettingsStore.hasBookSpeed(bookKey)) {
                  player.setSpeed(v);
                }
              },
            ),
          ),
          _SettingsTile(
            icon: Icons.bedtime_outlined,
            title: 'Default sleep timer',
            subtitle: _sleepTimerLabel(_defaultSleepTimer),
            onTap: () => showDefaultSleepTimerSheet(
              context,
              selected: _defaultSleepTimer,
              onChanged: (m) async {
                await SettingsStore.setDefaultSleepTimerMinutes(m);
                if (mounted) setState(() => _defaultSleepTimer = m);
              },
            ),
          ),
          _SegmentedTile(
            icon: Icons.volume_up_rounded,
            title: 'Volume boost',
            options: _boostOptions
                .map((d) => d == 0 ? 'Off' : '+$d dB')
                .toList(),
            selectedIndex:
                _boostOptions.indexOf(_volumeBoost).clamp(0, 3),
            onChanged: (i) async {
              final v = _boostOptions[i];
              await SettingsStore.setVolumeBoostDb(v);
              if (!mounted) return;
              setState(() => _volumeBoost = v);
              ref.read(playerServiceProvider).setVolumeBoost(v);
            },
          ),
          _PlayerAnimationTile(
            markMotion: _markMotion.clamp(0, 2),
            animationSyncDelay: _animationSyncDelay,
            onMarkMotionChanged: (i) async {
              await setMarkMotion(MarkMotion.values[i]);
              if (!mounted) return; // sign-out can tear this tab down
              setState(() => _markMotion = i);
            },
            onSyncDelayChanged: (ms) async {
              await SettingsStore.setAnimationSyncDelayMs(ms);
              AudioLevel.instance.setDelay(ms);
              if (!mounted) return;
              setState(() => _animationSyncDelay = ms);
            },
          ),
          _SwitchTile(
            icon: Icons.compress_rounded,
            title: 'Skip silence',
            subtitle: 'Shorten long pauses in narration',
            value: _skipSilence,
            onChanged: (v) async {
              await SettingsStore.setSkipSilence(v);
              if (!mounted) return;
              setState(() => _skipSilence = v);
              ref.read(playerServiceProvider).setSkipSilence(v);
            },
          ),
          _SwitchTile(
            icon: Icons.history_rounded,
            title: 'Auto-rewind on resume',
            subtitle: 'Rewind slightly when resuming playback',
            value: _autoRewind,
            onChanged: (v) async {
              await SettingsStore.setAutoRewindEnabled(v);
              if (!mounted) return;
              setState(() => _autoRewind = v);
            },
          ),
          _SwitchTile(
            icon: Icons.playlist_play_rounded,
            title: 'Auto-play next book',
            subtitle:
                'Start the next book when one finishes — only for books '
                'in a custom collection',
            value: _autoPlayNextBook,
            onChanged: (v) async {
              await SettingsStore.setAutoPlayNextBook(v);
              if (!mounted) return;
              setState(() => _autoPlayNextBook = v);
            },
          ),
          _SwitchTile(
            icon: Icons.phone_paused_outlined,
            title: 'Resume after interruptions',
            subtitle: 'Continue playback when a call or alert ends',
            value: _resumeAfterInterruption,
            onChanged: (v) async {
              await SettingsStore.setResumeAfterInterruption(v);
              if (!mounted) return;
              setState(() => _resumeAfterInterruption = v);
            },
          ),
          _SwitchTile(
            icon: Icons.linear_scale_rounded,
            title: 'Scrub within chapter',
            subtitle:
                'Seek bar covers the current chapter, not the whole book. '
                'Continue Listening and the widget show time left in the '
                'chapter too',
            value: _chapterScrub,
            onChanged: (v) async {
              await SettingsStore.setChapterScrub(v);
              // Home's card and the widget show chapter or book
              // figures by this; tell both now.
              ref.read(chapterScrubProvider.notifier).state = v;
              HomeWidgetSync.refresh();
              if (!mounted) return;
              setState(() => _chapterScrub = v);
            },
          ),
          _SwitchTile(
            icon: Icons.headphones_outlined,
            title: 'Headphone buttons skip',
            subtitle: 'Next and previous on headphones or in the car skip '
                'back and forward instead of changing chapter',
            value: _mediaButtonsSkip,
            onChanged: (v) async {
              await SettingsStore.setMediaButtonsSkip(v);
              if (!mounted) return;
              setState(() => _mediaButtonsSkip = v);
            },
          ),
      ],
    );
  }
}

class _PlayerAnimationTile extends StatelessWidget {
  final int markMotion;
  final int animationSyncDelay;
  final ValueChanged<int> onMarkMotionChanged;
  final ValueChanged<int> onSyncDelayChanged;

  const _PlayerAnimationTile({
    required this.markMotion,
    required this.animationSyncDelay,
    required this.onMarkMotionChanged,
    required this.onSyncDelayChanged,
  });

  static const _options = ['Reactive', 'Gentle', 'Pause'];
  static const _descriptions = [
    'Bars track real loudness via audio tap',
    'Bars use a smooth synthetic envelope',
    'Shows a static pause glyph while playing',
  ];

  void _openSheet(BuildContext context) {
    int localDelay = animationSyncDelay;
    // The sheet stays open on selection so the preview can be compared across
    // modes, so it tracks the choice itself rather than reading the (stale)
    // widget field captured when it opened.
    int localMotion = markMotion;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    showSagaSheet(context, (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => Padding(
        padding: EdgeInsets.only(bottom: bottomPad),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SagaSheetTitle('Player animation',
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8)),
            // Shows the selected motion for real: live audio when something is
            // playing, otherwise a recorded speech trace.
            const _MotionPreview(),
            ..._options.asMap().entries.map((e) {
              final selected = localMotion == e.key;
              return ListTile(
                selected: selected,
                title: Text(e.value, style: TextStyle(color: SagaColors.fg)),
                subtitle: Text(_descriptions[e.key],
                    style: TextStyle(color: SagaColors.fgSubtle, fontSize: 12)),
                trailing: selected
                    ? Icon(Icons.check_rounded, color: SagaColors.accent)
                    : null,
                // Applies immediately and keeps the sheet open — the preview
                // above switches so the modes can be compared side by side.
                onTap: () {
                  onMarkMotionChanged(e.key);
                  setLocal(() => localMotion = e.key);
                },
              );
            }),
            if (kDebugMode) _CaptureTraceTile(),
            if (localMotion == 0) ...[
              Divider(color: SagaColors.border, height: 24),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Row(
                  children: [
                    Icon(Icons.bluetooth_rounded,
                        color: SagaColors.fgSubtle, size: 16),
                    const SizedBox(width: 8),
                    Text('Animation sync delay',
                        style: TextStyle(
                            color: SagaColors.fg, fontSize: 14)),
                    const Spacer(),
                    Text(
                      localDelay == 0 ? 'Off' : '$localDelay ms',
                      style: TextStyle(
                          color: SagaColors.accentText,
                          fontSize: 14,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                child: Slider(
                  value: localDelay.toDouble(),
                  min: 0,
                  max: 400,
                  divisions: 40,
                  activeColor: SagaColors.accent,
                  inactiveColor: SagaColors.surfaceAlt,
                  onChanged: (v) => setLocal(() => localDelay = v.round()),
                  onChangeEnd: (v) => onSyncDelayChanged(v.round()),
                  // Announced in the slider's real unit — the default reads
                  // a raw percentage ("50%" for 200 ms).
                  semanticFormatterCallback: (v) => v.round() == 0
                      ? 'Off'
                      : '${v.round()} milliseconds',
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Text(
                  'Increase if the animation leads the audio — common on Bluetooth (try 100–200 ms).',
                  style: TextStyle(
                      color: SagaColors.fgMuted, fontSize: 12, height: 1.4),
                ),
              ),
            ] else
              const SizedBox(height: 8),
            // The sheet no longer closes on selection, so it needs a way out
            // that isn't "swipe it down and hope".
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Done',
                      style: TextStyle(color: SagaColors.accentText)),
                ),
              ),
            ),
          ],
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: SagaColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _openSheet(context),
            child: Row(
              children: [
                Icon(Icons.graphic_eq_rounded, color: SagaColors.accent, size: 22),
                const SizedBox(width: 16),
                Text('Player animation',
                    style: TextStyle(color: SagaColors.fg, fontSize: 16)),
                const SizedBox(width: 6),
                Icon(Icons.info_outline_rounded,
                    color: SagaColors.fgSubtle, size: 14),
              ],
            ),
          ),
          const Spacer(),
          ToggleButtons(
            isSelected: List.generate(_options.length, (i) => i == markMotion),
            onPressed: onMarkMotionChanged,
            borderColor: SagaColors.border,
            selectedBorderColor: SagaColors.accent,
            selectedColor: SagaColors.accentFg,
            fillColor: SagaColors.accent,
            color: SagaColors.fgMuted,
            borderRadius: BorderRadius.circular(8),
            constraints: const BoxConstraints(minWidth: 44, minHeight: 32),
            children: _options
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

/// The player-animation preview: one large mark in the playing state, showing
/// whichever motion is currently selected.
///
/// It reads through a [CannedAudioLevel], which prefers the real tap when a
/// book happens to be playing and otherwise replays a recorded speech trace.
/// One mark, one ticker — three small side-by-side previews were too small to
/// tell the motions apart and cost three tickers to run.
class _MotionPreview extends ConsumerStatefulWidget {
  const _MotionPreview();

  @override
  ConsumerState<_MotionPreview> createState() => _MotionPreviewState();
}

class _MotionPreviewState extends ConsumerState<_MotionPreview> {
  late final CannedAudioLevel _source;

  @override
  void initState() {
    super.initState();
    _source = CannedAudioLevel()..start();
  }

  @override
  void dispose() {
    _source.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Const-constructed by the parent, so its theme-driven rebuild never
    // reaches us — watch the theme directly.
    ref.watch(sagaThemeVariantProvider);
    // No motion selector here: AnimatedSagaMark already listens to
    // markMotionListenable, and selecting an option writes it — so the preview
    // follows the selection without being told.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Container(
        height: 132,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: SagaColors.surfaceAlt,
          borderRadius: BorderRadius.circular(14),
        ),
        child: AnimatedSagaMark(
          size: 84,
          state: SagaMarkState.playing,
          levelSource: _source,
        ),
      ),
    );
  }
}

/// Debug-only: records the loudness trace that backs [_MotionPreview] when
/// nothing is playing. See `lib/core/audio/speech_trace.dart` for the full
/// procedure — this button is step 2.
class _CaptureTraceTile extends StatefulWidget {
  @override
  State<_CaptureTraceTile> createState() => _CaptureTraceTileState();
}

class _CaptureTraceTileState extends State<_CaptureTraceTile> {
  bool _busy = false;

  Future<void> _capture() async {
    setState(() => _busy = true);
    final snippet = await AudioLevel.instance.captureTrace();
    await Clipboard.setData(ClipboardData(text: snippet));
    debugPrint(snippet);
    if (!mounted) return;
    setState(() => _busy = false);
    showSagaToast(context, 'Trace copied — paste into speech_trace.dart');
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(Icons.fiber_manual_record_rounded,
          color: SagaColors.fgSubtle, size: 18),
      title: Text(_busy ? 'Recording 6 s…' : 'Capture RMS trace (debug)',
          style: TextStyle(color: SagaColors.fgMuted, fontSize: 14)),
      subtitle: Text('Play a book first; sync delay must be 0',
          style: TextStyle(color: SagaColors.fgSubtle, fontSize: 12)),
      onTap: _busy ? null : _capture,
    );
  }
}
