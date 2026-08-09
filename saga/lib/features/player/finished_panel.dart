import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/plex/models/plex_book.dart';
import '../../core/providers.dart';
import '../../core/storage/completed_books_store.dart';
import '../../core/storage/listen_days_store.dart';
import '../../core/theme/saga_theme.dart';
import '../../core/utils/date_math.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/saga_mark.dart' show AnimatedSagaMark, SagaMarkState;
import '../../shared/widgets/saga_toast.dart';
import 'play_next.dart';
import 'player_service.dart';

// ── Finished panel (replaces the cover when a book completes) ──────────────────

class FinishedPanel extends ConsumerWidget {
  final AudioPlayerService service;
  final String bookKey;
  const FinishedPanel(
      {super.key, required this.service, required this.bookKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = CompletedBooksStore.completionCount(bookKey);
    final days = ListenDaysStore.daysListened(bookKey);
    final start = ListenDaysStore.startDate(bookKey);
    final dates = CompletedBooksStore.completionDates(bookKey);
    final finished = dates.isEmpty ? null : dates.last;
    // Calendar days, not Duration days: started 30 March, finished 31 March
    // in a spring-forward zone is 23h — `inDays` calls that 0 and the panel
    // said "1 day start to finish" for a two-day read.
    final spanDays = (start != null && finished != null)
        ? calendarDaysBetween(start, finished) + 1
        : null;
    final totalMs = service.totalBookDurationMs;
    final libraryKey = ref.watch(activeLibraryKeyProvider).valueOrNull;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.topRight,
            child: IconButton(
              icon: Icon(Icons.close, color: SagaColors.fgSubtle),
              onPressed: () {
                // Dismissing the panel is a "no" to the pending auto-advance
                // too — the X hiding the countdown while the timer kept
                // running meant the next book started against an explicit
                // dismissal.
                service.cancelAutoAdvance();
                service.justFinishedBook.value = null;
              },
              tooltip: 'Dismiss',
            ),
          ),
          const SizedBox(height: 24),
          // The bloom is the hero of the page.
          const AnimatedSagaMark(size: 120, state: SagaMarkState.finished),
          const SizedBox(height: 22),
          Text(
            'FINISHED',
            style: TextStyle(
              color: SagaColors.accent,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 3,
            ),
          ),
          if (finished != null) ...[
            const SizedBox(height: 6),
            Text(
              'on ${finished.day}/${finished.month}/${finished.year}',
              style: TextStyle(color: SagaColors.fgSubtle, fontSize: 12),
            ),
          ],
          const SizedBox(height: 22),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              _FinChip(value: '$count×', label: 'times listened'),
              if (spanDays != null)
                _FinChip(
                    value: '$spanDays ${spanDays == 1 ? 'day' : 'days'}',
                    label: 'start to finish')
              else if (days > 0)
                _FinChip(
                    value: '$days ${days == 1 ? 'day' : 'days'}',
                    label: 'days listened'),
              _FinChip(value: fmtDurationMs(totalMs), label: 'listened'),
            ],
          ),
          const SizedBox(height: 22),
          if (libraryKey != null)
            _NextInSeriesButton(
              libraryKey: libraryKey,
              bookKey: bookKey,
              service: service,
            ),
        ],
      ),
    );
  }
}

class _FinChip extends StatelessWidget {
  final String value;
  final String label;
  const _FinChip({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: SagaColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SagaColors.accent.withValues(alpha: 0.18)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              color: SagaColors.fg,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: SagaColors.fgSubtle,
              fontSize: 11,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _NextInSeriesButton extends ConsumerWidget {
  final String libraryKey;
  final String bookKey;
  final AudioPlayerService service;
  const _NextInSeriesButton({
    required this.libraryKey,
    required this.bookKey,
    required this.service,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final next =
        ref.watch(nextInSeriesProvider('$libraryKey|$bookKey')).valueOrNull;
    if (next == null) return const SizedBox.shrink();
    final col = next.$1;
    final book = next.$2;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.playlist_play_rounded,
                color: SagaColors.accent, size: 18),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Up next in ${col.name}',
                style: TextStyle(
                  color: SagaColors.fg,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // When auto-advance is armed this becomes a countdown with a way out.
        ValueListenableBuilder<int?>(
          valueListenable: service.autoAdvanceCountdown,
          builder: (context, secondsLeft, _) => Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _playNext(context, ref, book),
                  icon: const Icon(Icons.skip_next_rounded, size: 20),
                  label: Text(
                    secondsLeft != null
                        ? 'Playing in ${secondsLeft}s — ${book.title}'
                        : book.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SagaColors.accent,
                    foregroundColor: SagaColors.accentFg,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              if (secondsLeft != null)
                TextButton(
                  onPressed: service.cancelAutoAdvance,
                  child: Text('Cancel',
                      style:
                          TextStyle(color: SagaColors.fgMuted, fontSize: 13)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _playNext(
      BuildContext context, WidgetRef ref, PlexBook book) async {
    final ok = await playNextBook(
      service: service,
      book: book,
      loadTracks: (key) => ref.read(tracksProvider(key).future),
    );
    // Used to fail silently, which looked identical to a dead button.
    if (!ok && context.mounted) {
      showSagaToast(context, 'Could not start "${book.title}"', isError: true);
    }
  }
}
