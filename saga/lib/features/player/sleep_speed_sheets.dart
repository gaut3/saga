import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/playback_speed.dart';
import '../../core/plex/plex_client.dart';
import '../../core/providers.dart';
import '../../core/storage/settings_store.dart';
import '../../core/theme/saga_theme.dart';
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
                    child: _PresetTile(
                      speed: s,
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

void showSleepTimerSheet(BuildContext context, WidgetRef ref, bool isActive,
    {required AudioPlayerService service}) {
  final tracks = service.currentTracks;
  final m4bParam = tracks.length == 1
      ? PlexClient.instance.resolveM4bParam(tracks[0])
      : null;

  showSagaSheet<void>(context, (_) => Consumer(
    builder: (ctx, ref, _) {
        final m4bChapters = m4bParam != null
            ? ref.watch(m4bChaptersProvider(m4bParam)).valueOrNull
            : null;

        const timedOptions = [
          (label: '15 min', duration: Duration(minutes: 15), minutes: 15),
          (label: '30 min', duration: Duration(minutes: 30), minutes: 30),
          (label: '45 min', duration: Duration(minutes: 45), minutes: 45),
          (label: '60 min', duration: Duration(minutes: 60), minutes: 60),
        ];
        final defaultMinutes = SettingsStore.defaultSleepTimerMinutes;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Sleep timer',
                  style: TextStyle(
                      color: SagaColors.fg,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ListTile(
                leading: Icon(Icons.skip_next_outlined,
                    color: SagaColors.accent),
                title: Text('End of chapter',
                    style: TextStyle(color: SagaColors.fg)),
                trailing: defaultMinutes == -1
                    ? Icon(Icons.bedtime_outlined,
                        color: SagaColors.accent, size: 18)
                    : null,
                onTap: () {
                  final armed = ref
                      .read(sleepTimerProvider.notifier)
                      .setEndOfChapter(m4bChapters: m4bChapters);
                  Navigator.pop(ctx);
                  if (!armed) {
                    showSagaToast(context, kEndOfChapterUnknownMessage);
                  }
                },
              ),
              Divider(color: SagaColors.border, height: 8),
              ...timedOptions.map((opt) => ListTile(
                    title: Text(opt.label,
                        style: TextStyle(color: SagaColors.fg)),
                    trailing: defaultMinutes == opt.minutes
                        ? Icon(Icons.bedtime_outlined,
                            color: SagaColors.accent, size: 18)
                        : null,
                    onTap: () {
                      ref
                          .read(sleepTimerProvider.notifier)
                          .set(opt.duration);
                      Navigator.pop(ctx);
                    },
                  )),
              if (isActive) ...[
                Divider(color: SagaColors.fgSubtle),
                ListTile(
                  leading: const Icon(Icons.cancel_outlined,
                      color: Colors.redAccent),
                  title: const Text('Cancel timer',
                      style: TextStyle(color: Colors.redAccent)),
                  onTap: () {
                    ref.read(sleepTimerProvider.notifier).cancel();
                    Navigator.pop(ctx);
                  },
                ),
              ],
            ],
          ),
        );
      },
    ), scrollable: false);
}

/// A preset on the speed sheet. Filled with the accent when chosen, as the
/// segments in Settings are.
class _PresetTile extends StatelessWidget {
  final double speed;
  final bool selected;
  final VoidCallback onTap;

  const _PresetTile(
      {required this.speed, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '${fmtSpeed(speed)}×',
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
              // Seven share the width; at large text the label shrinks
              // rather than wraps.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    fmtSpeed(speed),
                    style: TextStyle(
                      color: selected ? SagaColors.accentFg : SagaColors.fg,
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
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
