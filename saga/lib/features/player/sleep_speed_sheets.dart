import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/playback_speed.dart';
import '../../core/plex/plex_client.dart';
import '../../core/providers.dart';
import '../../core/storage/settings_store.dart';
import '../../core/theme/saga_theme.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/choice_row.dart';
import '../../shared/widgets/saga_sheet.dart';
import '../../shared/widgets/saga_toast.dart';
import 'player_provider.dart';
import 'player_service.dart';

/// Speed picker sheet, for the playing book and for the default in Settings:
/// a fine-tune row in 0.05 steps over the presets. The steps apply at once
/// and leave the sheet open, so the change is heard while tuning; a preset
/// sets and closes.
void showSpeedSheet(
  BuildContext context, {
  String title = 'Playback speed',
  required double speed,
  required ValueChanged<double> onChanged,
}) {
  final bottomPad = MediaQuery.of(context).padding.bottom;
  showSagaSheet<void>(
      context,
      (_) => _SpeedSheet(
            title: title,
            initial: snapSpeed(speed),
            onChanged: onChanged,
            bottomPad: bottomPad,
          ));
}

class _SpeedSheet extends StatefulWidget {
  final String title;
  final double initial;
  final ValueChanged<double> onChanged;
  final double bottomPad;

  const _SpeedSheet({
    required this.title,
    required this.initial,
    required this.onChanged,
    required this.bottomPad,
  });

  @override
  State<_SpeedSheet> createState() => _SpeedSheetState();
}

class _SpeedSheetState extends State<_SpeedSheet> {
  late double _speed = widget.initial;

  void _set(double speed) {
    if (speed == _speed) return;
    setState(() => _speed = speed);
    widget.onChanged(speed);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: widget.bottomPad + 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SagaSheetTitle(widget.title,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _StepButton(
                  icon: Icons.remove_rounded,
                  label: 'Slower',
                  onTap: _speed > kMinSpeed
                      ? () => _set(stepSpeed(_speed, -1))
                      : null,
                ),
                SizedBox(
                  width: 120,
                  // Read out on each step: the number is the only feedback
                  // a step gives besides the audio.
                  child: Semantics(
                    liveRegion: true,
                    label: 'Speed ${fmtSpeed(_speed)}×',
                    excludeSemantics: true,
                    child: Text(
                      '${fmtSpeed(_speed)}×',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: SagaColors.fg,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
                _StepButton(
                  icon: Icons.add_rounded,
                  label: 'Faster',
                  onTap: _speed < kMaxSpeed
                      ? () => _set(stepSpeed(_speed, 1))
                      : null,
                ),
              ],
            ),
          ),
          // Inset to the text margin like the Device sheet's dividers.
          Divider(
              color: SagaColors.border, height: 1, indent: 16, endIndent: 16),
          // One row of tiles, not a list: the chosen speed is the filled
          // one, found at a glance instead of by reading down to a check
          // mark — and none is filled when the speed sits between them.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                for (final s in kSpeedPresets) ...[
                  if (s != kSpeedPresets.first) const SizedBox(width: 6),
                  Expanded(
                    child: _OptionTile(
                      label: fmtSpeed(s),
                      semanticLabel: '${fmtSpeed(s)}×',
                      selected: _speed == s,
                      onTap: () {
                        _set(s);
                        Navigator.pop(context);
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 48px so it can be tapped repeatedly without aiming; on `surfaceAlt`
/// because the sheet itself is `surface`.
class _StepButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _StepButton({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Material(
        color: SagaColors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(icon,
                size: 22,
                color: onTap == null ? SagaColors.fgSubtle : SagaColors.fg),
          ),
        ),
      ),
    );
  }
}

/// One of a row of options on a sheet (speeds, sleep lengths). Filled with
/// the accent when chosen, as the segments in Settings are.
class _OptionTile extends StatelessWidget {
  final String label;
  final String? semanticLabel;
  final bool selected;

  /// A small moon before the label: this length is the default sleep timer.
  final bool isDefault;
  final VoidCallback onTap;

  const _OptionTile({
    required this.label,
    this.semanticLabel,
    required this.selected,
    this.isDefault = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? SagaColors.accentFg : SagaColors.fg;
    return Semantics(
      button: true,
      selected: selected,
      label: '${semanticLabel ?? label}${isDefault ? ', default' : ''}',
      excludeSemantics: true,
      child: Material(
        color: selected ? SagaColors.accent : SagaColors.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 48,
            child: Center(
              // The tiles share the width; at large text the label shrinks
              // rather than wraps.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isDefault) ...[
                        Icon(Icons.bedtime_outlined,
                            size: 14,
                            color: selected
                                ? SagaColors.accentFg
                                : SagaColors.accent),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        label,
                        style: TextStyle(
                          color: fg,
                          fontSize: 14,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Sleep timer ───────────────────────────────────────────────────────────────

const _sleepMinutes = [15, 30, 45, 60];
const _sleepStep = Duration(minutes: 5);

/// The choices both sleep sheets share: end of chapter as a row of its own
/// (a different kind of choice from a length), then the lengths as tiles.
/// [selected] and [defaultMinutes] use the setting's encoding: -1 is end of
/// chapter, 0 is off, anything else is minutes.
class _SleepChoices extends StatelessWidget {
  final int? selected;
  final int? defaultMinutes;
  final bool showOff;
  final ValueChanged<int> onPick;

  const _SleepChoices({
    required this.selected,
    this.defaultMinutes,
    this.showOff = false,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showOff)
            ChoiceRow(
              icon: Icons.bedtime_off_outlined,
              title: 'Off',
              subtitle: 'The sleep button opens the sheet',
              selected: selected == 0,
              onTap: () => onPick(0),
            ),
          if (showOff) Divider(color: SagaColors.border, height: 1),
          ChoiceRow(
            icon: Icons.skip_next_outlined,
            title: 'End of chapter',
            selected: selected == -1,
            trailing: defaultMinutes == -1
                ? Tooltip(
                    message: 'Default',
                    child: Icon(Icons.bedtime_outlined,
                        color: SagaColors.accent, size: 18),
                  )
                : null,
            onTap: () => onPick(-1),
          ),
          Divider(color: SagaColors.border, height: 1),
          const SizedBox(height: 16),
          Row(
            children: [
              for (final m in _sleepMinutes) ...[
                if (m != _sleepMinutes.first) const SizedBox(width: 6),
                Expanded(
                  child: _OptionTile(
                    label: '$m min',
                    selected: selected == m,
                    isDefault: defaultMinutes == m,
                    onTap: () => onPick(m),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// The player's sleep sheet. While a timed countdown runs, a − / + row shows
/// the time left and moves it five minutes at once, the sheet staying open;
/// an end-of-chapter countdown shows its time left without the steps.
void showSleepTimerSheet(BuildContext context,
    {required AudioPlayerService service}) {
  final bottomPad = MediaQuery.of(context).padding.bottom;
  showSagaSheet<void>(context,
      (_) => _SleepSheet(service: service, bottomPad: bottomPad));
}

class _SleepSheet extends ConsumerStatefulWidget {
  final AudioPlayerService service;
  final double bottomPad;

  const _SleepSheet({required this.service, required this.bottomPad});

  @override
  ConsumerState<_SleepSheet> createState() => _SleepSheetState();
}

class _SleepSheetState extends ConsumerState<_SleepSheet> {
  // The time left is read, not watched: it falls by itself.
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _pick(int minutes) {
    final timer = ref.read(sleepTimerProvider.notifier);
    if (minutes == -1) {
      final tracks = widget.service.currentTracks;
      final m4bParam = tracks.length == 1
          ? PlexClient.instance.resolveM4bParam(tracks[0])
          : null;
      final m4bChapters = m4bParam != null
          ? ref.read(m4bChaptersProvider(m4bParam)).valueOrNull
          : null;
      final armed = timer.setEndOfChapter(m4bChapters: m4bChapters);
      if (!armed) showSagaToast(context, kEndOfChapterUnknownMessage);
    } else {
      timer.set(Duration(minutes: minutes));
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(sleepTimerProvider) != null;
    final timer = ref.read(sleepTimerProvider.notifier);
    final chapter = timer.isEndOfChapter;
    final remaining = active ? timer.remaining : null;
    final defaultMinutes = SettingsStore.defaultSleepTimerMinutes;

    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: widget.bottomPad + 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SagaSheetTitle('Sleep timer',
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8)),
          if (remaining != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (!chapter)
                    _StepButton(
                      icon: Icons.remove_rounded,
                      label: 'Five minutes less',
                      onTap: remaining > kMinSleepTimer
                          ? () => setState(() => timer.adjust(-_sleepStep))
                          : null,
                    ),
                  SizedBox(
                    width: 160,
                    child: Semantics(
                      label: 'Pauses in ${fmtDuration(remaining)}',
                      excludeSemantics: true,
                      child: Text(
                        fmtDuration(remaining),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: SagaColors.fg,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                  if (!chapter)
                    _StepButton(
                      icon: Icons.add_rounded,
                      label: 'Five minutes more',
                      onTap: remaining < kMaxSleepTimer
                          ? () => setState(() => timer.adjust(_sleepStep))
                          : null,
                    ),
                ],
              ),
            ),
            Divider(
                color: SagaColors.border, height: 1, indent: 16, endIndent: 16),
          ],
          _SleepChoices(
            selected: !active
                ? null
                : chapter
                    ? -1
                    : timer.presetMinutes,
            defaultMinutes: defaultMinutes,
            onPick: _pick,
          ),
          if (active) ...[
            const SizedBox(height: 16),
            Divider(
                color: SagaColors.border, height: 1, indent: 16, endIndent: 16),
            ListTile(
              leading:
                  const Icon(Icons.cancel_outlined, color: Colors.redAccent),
              title: const Text('Cancel timer',
                  style: TextStyle(color: Colors.redAccent)),
              onTap: () {
                timer.cancel();
                Navigator.pop(context);
              },
            ),
          ] else
            const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// Settings' default sleep timer: the same choices, plus Off.
void showDefaultSleepTimerSheet(
  BuildContext context, {
  required int selected,
  required ValueChanged<int> onChanged,
}) {
  final bottomPad = MediaQuery.of(context).padding.bottom;
  showSagaSheet<void>(
      context,
      (ctx) => SingleChildScrollView(
            padding: EdgeInsets.only(bottom: bottomPad + 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SagaSheetTitle('Default sleep timer',
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8)),
                _SleepChoices(
                  selected: selected,
                  showOff: true,
                  onPick: (m) {
                    onChanged(m);
                    Navigator.pop(ctx);
                  },
                ),
              ],
            ),
          ));
}
