import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/plex/plex_client.dart';
import '../../core/providers.dart';
import '../../core/storage/settings_store.dart';
import '../../core/theme/saga_theme.dart';
import '../../shared/widgets/saga_sheet.dart';
import 'player_provider.dart';
import 'player_service.dart';

const _speeds = [0.75, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0];

/// Speed picker sheet — same pattern as the sleep-timer picker, replacing
/// the old tap-to-cycle button so every action-row control opens a sheet.
void showSpeedSheet(BuildContext context,
    {required AudioPlayerService service, String? bookKey}) {
  final bottomPad = MediaQuery.of(context).padding.bottom;
  showSagaSheet<void>(context, (_) => Consumer(
    builder: (ctx, ref, _) {
      final current = ref.watch(playbackSpeedProvider).valueOrNull ??
          service.player.speed;
      return Padding(
        padding: EdgeInsets.only(bottom: bottomPad + 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SagaSheetTitle('Playback speed',
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8)),
            ..._speeds.map((s) => ListTile(
                  // Announced as "selected" — the check mark alone is silent.
                  selected: current == s,
                  title:
                      Text('$s×', style: TextStyle(color: SagaColors.fg)),
                  trailing: current == s
                      ? Icon(Icons.check_rounded, color: SagaColors.accent)
                      : null,
                  onTap: () {
                    // playbackSpeedProvider follows the service's own state,
                    // so setting the speed is all the UI update there is.
                    service.setSpeed(s);
                    if (bookKey != null) {
                      SettingsStore.setBookSpeed(bookKey, s);
                    }
                    Navigator.pop(ctx);
                  },
                )),
          ],
        ),
      );
    },
  ));
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
                  ref
                      .read(sleepTimerProvider.notifier)
                      .setEndOfChapter(m4bChapters: m4bChapters);
                  Navigator.pop(ctx);
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
