import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import '../../core/theme/saga_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/m4b_chapter_reader.dart';
import '../../core/plex/models/plex_book.dart';
import '../../core/plex/models/plex_track.dart';
import '../../core/storage/completed_books_store.dart';
import '../../core/storage/listen_days_store.dart';
import '../../core/storage/settings_store.dart';
import '../../core/providers.dart';
import '../../core/storage/named_bookmark_store.dart';
import '../../core/storage/playback_log_store.dart';
import '../../core/cast/cast_service.dart';
import '../../core/plex/plex_client.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/saga_mark.dart' show AnimatedSagaMark, SagaMarkState;
import '../../shared/widgets/saga_sheet.dart';
import '../../shared/widgets/saga_toast.dart';
import 'player_provider.dart';
import 'player_service.dart';

class PlayerScreen extends ConsumerWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(playerServiceProvider);

    return Scaffold(
      backgroundColor: SagaColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: SagaColors.fg,
        title: const Text('Now Playing', style: TextStyle(fontSize: 16)),
      ),
      body: StreamBuilder<MediaItem?>(
        stream: service.mediaItem,
        builder: (context, snap) {
          final item = snap.data;
          final bookKey = service.currentBookRatingKey;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TopPills(service: service, bookKey: bookKey),
              Expanded(
                child: ValueListenableBuilder<String?>(
                  valueListenable: service.justFinishedBook,
                  builder: (context, finishedKey, _) {
                    if (finishedKey != null && finishedKey == bookKey) {
                      return _FinishedPanel(
                          service: service, bookKey: bookKey!);
                    }
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 8),
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: 1.0,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: _CoverArt(artUri: item?.artUri),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              _TrackInfo(item: item),
              const SizedBox(height: 4),
              _ProgressBar(service: service),
              _Controls(service: service),
              const SizedBox(height: 4),
              _BottomActions(service: service, bookKey: bookKey),
              const SizedBox(height: 20),
            ],
          );
        },
      ),
    );
  }
}

// ── Top pill buttons: Chapters | Bookmarks ────────────────────────────────────

class _TopPills extends ConsumerWidget {
  final AudioPlayerService service;
  final String? bookKey;

  const _TopPills({required this.service, required this.bookKey});

  String? _m4bParam(List<PlexTrack> tracks) {
    if (tracks.length != 1) return null;
    return PlexClient.instance.resolveM4bParam(tracks[0]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookmarkCount = bookKey != null
        ? ref.watch(bookmarkNotifierProvider(bookKey!)).length
        : 0;

    final tracks = service.currentTracks;
    final param = _m4bParam(tracks);

    final m4bAsync = param != null
        ? ref.watch(m4bChaptersProvider(param))
        : const AsyncData<List<M4bChapter>>([]);

    final m4bChapters = m4bAsync.valueOrNull ?? [];
    // Don't show a count while M4B chapters are still being parsed — a single
    // M4B track would otherwise briefly show "Chapters (1)" instead of e.g. "Chapters (22)".
    final chapterCount = m4bChapters.isNotEmpty
        ? m4bChapters.length
        : (param != null && m4bAsync.isLoading ? 0 : tracks.length);

    final sessionCount = bookKey != null
        ? PlaybackLogStore.getLog(bookKey!).where((e) => e.type == 'play').length
        : 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Row(
        children: [
          if (chapterCount > 1) ...[
            _PillButton(
              icon: Icons.list_rounded,
              label: 'Chapters ($chapterCount)',
              onTap: () => _showChapters(context, param),
            ),
            const SizedBox(width: 8),
          ],
          _PillButton(
            icon: Icons.bookmarks_outlined,
            label: bookmarkCount > 0
                ? 'Bookmarks ($bookmarkCount)'
                : 'Bookmarks',
            onTap: () {
              if (bookKey != null) _showBookmarks(context, ref, bookKey!);
            },
          ),
          if (sessionCount > 0) ...[
            const SizedBox(width: 8),
            _PillButton(
              icon: Icons.history_rounded,
              label: 'Sessions ($sessionCount)',
              onTap: () {
                if (bookKey != null) _showSessions(context, bookKey!);
              },
            ),
          ],
        ],
      ),
    );
  }



  void _showChapters(BuildContext context, String? m4bKey) {
    final tracks = service.currentTracks;
    final currentIdx = service.player.currentIndex ?? 0;

    showSagaSheet<void>(context, (_) => Consumer(
        builder: (ctx, ref, _) {
          final m4bAsync = m4bKey != null
              ? ref.watch(m4bChaptersProvider(m4bKey))
              : const AsyncData<List<M4bChapter>>([]);

          final m4bChapters = m4bAsync.valueOrNull ?? [];

          return DraggableScrollableSheet(
            initialChildSize: 0.6,
            minChildSize: 0.3,
            maxChildSize: 0.9,
            expand: false,
            builder: (ctx2, scrollController) => Column(
              children: [
                const _SheetHandle(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Text('Chapters',
                      style: TextStyle(
                          color: SagaColors.fg,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                ),
                if (m4bAsync.isLoading)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: AnimatedSagaMark(size: 36, state: SagaMarkState.buffering),
                  ),
                Expanded(
                  child: m4bChapters.isNotEmpty
                      ? _M4bChapterList(
                          chapters: m4bChapters,
                          service: service,
                          scrollController: scrollController,
                        )
                      : _PlexTrackList(
                          tracks: tracks,
                          currentIdx: currentIdx,
                          service: service,
                          scrollController: scrollController,
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showBookmarks(BuildContext context, WidgetRef ref, String bookKey) {
    showSagaSheet<void>(context, (_) => Consumer(
      builder: (ctx, innerRef, _) {
          final bookmarks = innerRef.watch(bookmarkNotifierProvider(bookKey));
          return DraggableScrollableSheet(
            initialChildSize: 0.5,
            minChildSize: 0.3,
            maxChildSize: 0.9,
            expand: false,
            builder: (ctx2, scrollController) => Column(
              children: [
                const _SheetHandle(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Text('Bookmarks',
                      style: TextStyle(
                          color: SagaColors.fg,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  child: bookmarks.isEmpty
                      ? Center(
                          child: Text('No bookmarks yet',
                              style: TextStyle(color: SagaColors.fgSubtle)))
                      : ListView.builder(
                          controller: scrollController,
                          itemCount: bookmarks.length,
                          itemBuilder: (context, i) {
                            final bm = bookmarks[i];
                            return ListTile(
                              leading: Icon(Icons.bookmark,
                                  color: SagaColors.accent),
                              title: Text(bm.label,
                                  style: TextStyle(
                                      color: SagaColors.fg, fontSize: 14)),
                              subtitle: bm.note != null && bm.note!.isNotEmpty
                                  ? Text(bm.note!,
                                      style: TextStyle(
                                          color: SagaColors.fgSubtle,
                                          fontSize: 11,
                                          fontStyle: FontStyle.italic),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis)
                                  : null,
                              trailing: IconButton(
                                icon: Icon(Icons.delete_outline,
                                    color: SagaColors.fgSubtle),
                                onPressed: () {
                                  innerRef
                                      .read(bookmarkNotifierProvider(bookKey)
                                          .notifier)
                                      .remove(bm.id);
                                },
                              ),
                              onTap: () {
                                service.seek(
                                    Duration(milliseconds: bm.positionMs));
                                Navigator.pop(ctx);
                              },
                              onLongPress: () =>
                                  _editBookmark(ctx, innerRef, bookKey, bm),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _editBookmark(BuildContext context, WidgetRef ref,
      String bookKey, NamedBookmark bm) async {
    final labelCtrl = TextEditingController(text: bm.label);
    final noteCtrl = TextEditingController(text: bm.note ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: SagaColors.surface,
        title: Text('Edit bookmark', style: TextStyle(color: SagaColors.fg)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: labelCtrl,
              style: TextStyle(color: SagaColors.fg),
              decoration: InputDecoration(
                labelText: 'Label',
                labelStyle: TextStyle(color: SagaColors.fgMuted),
                enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: SagaColors.border)),
                focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: SagaColors.accent)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteCtrl,
              style: TextStyle(color: SagaColors.fg),
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Note (optional)',
                labelStyle: TextStyle(color: SagaColors.fgMuted),
                enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: SagaColors.border)),
                focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: SagaColors.accent)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child:
                Text('Cancel', style: TextStyle(color: SagaColors.fgMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Save', style: TextStyle(color: SagaColors.accent)),
          ),
        ],
      ),
    );
    if (saved == true) {
      final label = labelCtrl.text.trim();
      final note = noteCtrl.text.trim();
      if (label.isEmpty) return;
      final updated = bm.copyWith(
        label: label,
        note: note.isEmpty ? null : note,
      );
      ref.read(bookmarkNotifierProvider(bookKey).notifier).update(updated);
    }
  }

  void _showSessions(BuildContext context, String bookKey) {
    final events = PlaybackLogStore.getLog(bookKey);
    // Pair play→pause into sessions (newest first)
    final sessions = <({DateTime start, Duration? duration})>[];
    for (int i = 0; i < events.length; i++) {
      if (events[i].type != 'play') continue;
      Duration? dur;
      if (i + 1 < events.length && events[i + 1].type == 'pause') {
        dur = events[i + 1].timestamp.difference(events[i].timestamp);
      }
      sessions.add((start: events[i].timestamp, duration: dur));
    }
    sessions.sort((a, b) => b.start.compareTo(a.start));

    String fmtTime(DateTime t) {
      final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
      final suffix = t.hour >= 12 ? 'PM' : 'AM';
      return '$h:${t.minute.toString().padLeft(2, '0')} $suffix';
    }

    String fmtDate(DateTime t) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final day = DateTime(t.year, t.month, t.day);
      if (day == today) return 'Today';
      if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
      return '${t.day}/${t.month}/${t.year}';
    }

    showSagaSheet<void>(context, (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        builder: (_, ctrl) => Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: SagaColors.fgSubtle.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(children: [
                Text('Sessions',
                    style: TextStyle(
                        color: SagaColors.fg,
                        fontSize: 17,
                        fontWeight: FontWeight.w700)),
              ]),
            ),
            Expanded(
              child: ListView.builder(
                controller: ctrl,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: sessions.length,
                itemBuilder: (_, i) {
                  final s = sessions[i];
                  return Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: SagaColors.accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.play_arrow,
                              color: SagaColors.accent, size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                fmtDate(s.start),
                                style: TextStyle(
                                    color: SagaColors.fg,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600),
                              ),
                              Text(
                                fmtTime(s.start) +
                                    (s.duration != null
                                        ? '  ·  ${fmtDurationMs(s.duration!.inMilliseconds)}'
                                        : ''),
                                style: TextStyle(
                                    color: SagaColors.fgSubtle, fontSize: 12.5),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _PillButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: SagaColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: SagaColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: SagaColors.fgMuted),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(color: SagaColors.fgMuted, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: SagaColors.fgSubtle,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

// ── Cover art ─────────────────────────────────────────────────────────────────

class _CoverArt extends StatelessWidget {
  final Uri? artUri;
  const _CoverArt({this.artUri});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: artUri != null ? _buildImage(artUri!) : _placeholder(),
    );
  }

  Widget _buildImage(Uri uri) {
    final ImageProvider provider = uri.scheme == 'file'
        ? FileImage(File(uri.toFilePath()))
        : ResizeImage(NetworkImage(uri.toString()), width: 600);
    return Stack(
      fit: StackFit.expand,
      children: [
        // Blurred, cropped fill — hides letterbox bars
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Image(
            image: provider,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(color: SagaColors.surface),
          ),
        ),
        Container(color: Colors.black.withValues(alpha: 0.30)),
        // Contained artwork centred on top
        Image(
          image: provider,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => _placeholder(),
        ),
      ],
    );
  }

  Widget _placeholder() => Container(
        color: SagaColors.surface,
        child: Center(
            child: Icon(Icons.book, size: 80, color: SagaColors.fgSubtle)),
      );
}

// ── Track info ────────────────────────────────────────────────────────────────

class _TrackInfo extends StatelessWidget {
  final MediaItem? item;
  const _TrackInfo({this.item});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          Text(
            item?.title ?? '',
            style: TextStyle(
                color: SagaColors.fg,
                fontSize: 18,
                fontWeight: FontWeight.bold),
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            item?.album ?? '',
            style: TextStyle(color: SagaColors.accent, fontSize: 13),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (item?.artist != null)
            Text(item!.artist!,
                style: TextStyle(color: SagaColors.fgMuted, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

// ── Progress bar — shows book-level progress ──────────────────────────────────

class _ProgressBar extends StatefulWidget {
  final AudioPlayerService service;
  const _ProgressBar({required this.service});

  @override
  State<_ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends State<_ProgressBar> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: widget.service.positionStream,
      builder: (context, posSnap) {
        // Use book-level absolute position so multi-track books show overall
        // progress rather than per-chapter progress.
        final totalMs = widget.service.totalBookDurationMs;
        final absMs = widget.service.absolutePositionMs;
        // posSnap drives rebuilds; the actual value used is absolutePositionMs.
        posSnap.data;

        final progress = totalMs > 0
            ? (absMs / totalMs).clamp(0.0, 1.0)
            : 0.0;
        final displayValue = _dragValue ?? progress;
        final displayAbsMs = _dragValue != null
            ? (_dragValue! * totalMs).round()
            : absMs;
        final displayPos = Duration(milliseconds: displayAbsMs);
        final displayDur = Duration(milliseconds: totalMs > 0 ? totalMs : absMs);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  // Slider internal padding equals the overlay radius (14 px)
                  // on each side — thumb center travels from edge to (width-edge).
                  const edge = 14.0;
                  final thumbX = edge +
                      displayValue * (constraints.maxWidth - 2 * edge);
                  const labelW = 62.0;
                  final labelLeft =
                      (thumbX - labelW / 2).clamp(0.0, constraints.maxWidth - labelW);
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          thumbShape:
                              const RoundSliderThumbShape(enabledThumbRadius: 6),
                          overlayShape:
                              const RoundSliderOverlayShape(overlayRadius: 14),
                          activeTrackColor: SagaColors.accent,
                          inactiveTrackColor: SagaColors.surfaceAlt,
                          thumbColor: SagaColors.accent,
                        ),
                        child: Slider(
                          value: displayValue,
                          onChanged: (v) => setState(() => _dragValue = v),
                          onChangeEnd: (v) {
                            setState(() => _dragValue = null);
                            widget.service.seekAbsolute(
                                Duration(milliseconds: (v * totalMs).round()));
                          },
                          semanticFormatterCallback: (v) => fmtDuration(
                              Duration(milliseconds: (v * totalMs).round())),
                        ),
                      ),
                      if (_dragValue != null)
                        Positioned(
                          left: labelLeft,
                          top: -28,
                          child: Container(
                            width: labelW,
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: SagaColors.surface,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              fmtDuration(displayPos),
                              style: TextStyle(
                                color: SagaColors.fg,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(fmtDuration(displayPos),
                        style: TextStyle(
                            color: SagaColors.fgMuted, fontSize: 12)),
                    Text(fmtDuration(displayDur),
                        style: TextStyle(
                            color: SagaColors.fgMuted, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

}

// ── Playback controls ─────────────────────────────────────────────────────────

class _Controls extends StatelessWidget {
  final AudioPlayerService service;
  const _Controls({required this.service});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlaybackState>(
      stream: service.playbackState,
      builder: (context, snap) {
        final playing = snap.data?.playing ?? false;
        final loading =
            snap.data?.processingState == AudioProcessingState.loading ||
            snap.data?.processingState == AudioProcessingState.buffering;

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              iconSize: 36,
              icon: const Icon(Icons.skip_previous_rounded),
              color: SagaColors.fgMuted,
              tooltip: 'Skip to previous',
              onPressed: service.skipToPrevious,
            ),
            IconButton(
              iconSize: 28,
              icon: const Icon(Icons.replay_30_rounded),
              color: SagaColors.fgMuted,
              tooltip:
                  'Rewind ${SettingsStore.skipBackwardSeconds} seconds',
              onPressed: () async {
                final pos = await service.positionStream.first;
                final skip = SettingsStore.skipBackwardSeconds * 1000;
                service.seek(Duration(
                    milliseconds:
                        (pos.inMilliseconds - skip).clamp(0, 999999999)));
              },
            ),
            const SizedBox(width: 8),
            Semantics(
              label: playing ? 'Pause' : 'Play',
              button: true,
              excludeSemantics: true,
              child: GestureDetector(
                onTap: playing ? service.pause : service.play,
                child: AnimatedSagaMark(
                  size: 56,
                  state: loading
                      ? SagaMarkState.buffering
                      : playing
                          ? SagaMarkState.playing
                          : SagaMarkState.paused,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              iconSize: 28,
              icon: const Icon(Icons.forward_30_rounded),
              color: SagaColors.fgMuted,
              tooltip:
                  'Skip forward ${SettingsStore.skipForwardSeconds} seconds',
              onPressed: () async {
                final totalMs = service.totalBookDurationMs;
                final skip = SettingsStore.skipForwardSeconds * 1000;
                service.seekAbsolute(Duration(
                    milliseconds: (service.absolutePositionMs + skip)
                        .clamp(0, totalMs > 0 ? totalMs : 999999999)));
              },
            ),
            IconButton(
              iconSize: 36,
              icon: const Icon(Icons.skip_next_rounded),
              color: SagaColors.fgMuted,
              tooltip: 'Skip to next',
              onPressed: service.skipToNext,
            ),
          ],
        );
      },
    );
  }
}

// ── Bottom action row ─────────────────────────────────────────────────────────

class _BottomActions extends ConsumerWidget {
  final AudioPlayerService service;
  final String? bookKey;

  static const _speeds = [0.75, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0];

  const _BottomActions({required this.service, required this.bookKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final speed = ref.watch(playbackSpeedProvider);
    final timerEnd = ref.watch(sleepTimerProvider);

    return ValueListenableBuilder<bool>(
      valueListenable: service.canUndoSeekNotifier,
      builder: (_, canUndo, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _ActionButton(
              label: '${speed}x',
              icon: Icons.speed,
              active: speed != 1.0,
              semanticLabel: 'Playback speed: $speed×',
              onTap: () {
                final idx = _speeds.indexOf(speed);
                final next = _speeds[(idx + 1) % _speeds.length];
                ref.read(playbackSpeedProvider.notifier).state = next;
                service.setSpeed(next);
                if (bookKey != null) {
                  SettingsStore.setBookSpeed(bookKey!, next);
                }
              },
            ),
            _ActionButton(
              label: 'Bookmark',
              icon: Icons.bookmark_add_outlined,
              semanticLabel: 'Add bookmark',
              onTap: () => _addBookmark(context, ref),
            ),
            _ActionButton(
              label: 'Cast',
              icon: Icons.cast,
              semanticLabel: 'Cast to device',
              onTap: () => _showCastSheet(context),
            ),
            _SleepTimerButton(
              service: service,
              timerEnd: timerEnd,
              onTap: () {
                final isActive = timerEnd != null;
                final defaultMinutes = SettingsStore.defaultSleepTimerMinutes;
                if (!isActive && defaultMinutes != 0) {
                  _startDefaultSleepTimer(context, ref, defaultMinutes);
                } else {
                  _showSleepTimer(context, ref, isActive);
                }
              },
            ),
            _ActionButton(
              label: 'Undo',
              icon: Icons.undo,
              active: canUndo,
              semanticLabel: 'Undo seek',
              onTap: canUndo ? service.undoSeek : () {},
            ),
          ],
        ),
      ),
    );
  }

  void _startDefaultSleepTimer(BuildContext context, WidgetRef ref, int minutes) {
    if (minutes == -1) {
      final tracks = service.currentTracks;
      final m4bParam = tracks.length == 1
          ? PlexClient.instance.resolveM4bParam(tracks[0])
          : null;
      final m4bChapters = m4bParam != null
          ? ref.read(m4bChaptersProvider(m4bParam)).valueOrNull
          : null;
      ref.read(sleepTimerProvider.notifier).setEndOfChapter(m4bChapters: m4bChapters);
      showSagaToast(context, 'Sleep timer: end of chapter');
    } else {
      ref.read(sleepTimerProvider.notifier).set(Duration(minutes: minutes));
      showSagaToast(context, 'Sleep timer: $minutes min');
    }
  }

  Future<void> _addBookmark(BuildContext context, WidgetRef ref) async {
    final key = bookKey;
    if (key == null) return;
    final track = service.currentTrackInfo;
    if (track == null) return;

    final positionMs = service.player.position.inMilliseconds;
    final mins = positionMs ~/ 60000;
    final secs =
        ((positionMs % 60000) / 1000).round().toString().padLeft(2, '0');
    final defaultLabel = '${track.title} • $mins:$secs';

    final controller = TextEditingController(text: defaultLabel);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: SagaColors.surface,
        title: Text('Add bookmark',
            style: TextStyle(color: SagaColors.fg, fontSize: 16)),
        content: TextField(
          controller: controller,
          style: TextStyle(color: SagaColors.fg),
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Bookmark name',
            hintStyle: TextStyle(color: SagaColors.fgSubtle),
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: SagaColors.border)),
            focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: SagaColors.accent)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: SagaColors.fgMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Save', style: TextStyle(color: SagaColors.accent)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final label = controller.text.trim().isEmpty ? defaultLabel : controller.text.trim();
    final bm = NamedBookmark(
      id: _uuid(),
      bookRatingKey: key,
      trackRatingKey: track.ratingKey,
      positionMs: positionMs,
      label: label,
      createdAt: DateTime.now(),
    );
    ref.read(bookmarkNotifierProvider(key).notifier).add(bm);

    if (context.mounted) {
      showSagaToast(context, 'Bookmark added: $label');
    }
  }

  void _showCastSheet(BuildContext context) {
    showSagaSheet<void>(context, (_) => _CastSheet(service: service),
        scrollable: false);
  }

  void _showSleepTimer(BuildContext context, WidgetRef ref, bool isActive) {
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
                Text('Sleep Timer',
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
}

String _uuid() {
  final now = DateTime.now().microsecondsSinceEpoch;
  return now.toRadixString(16).padLeft(16, '0');
}

// ── Sleep timer button with live countdown ────────────────────────────────────

class _SleepTimerButton extends StatefulWidget {
  final AudioPlayerService service;
  final DateTime? timerEnd;
  final VoidCallback onTap;

  const _SleepTimerButton({
    required this.service,
    required this.timerEnd,
    required this.onTap,
  });

  @override
  State<_SleepTimerButton> createState() => _SleepTimerButtonState();
}

class _SleepTimerButtonState extends State<_SleepTimerButton> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _startTick();
  }

  @override
  void didUpdateWidget(_SleepTimerButton old) {
    super.didUpdateWidget(old);
    if (old.timerEnd != widget.timerEnd) _startTick();
  }

  void _startTick() {
    _tick?.cancel();
    if (widget.timerEnd != null) {
      _tick = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String _label() {
    final end = widget.timerEnd;
    if (end == null) return 'Sleep';
    final r = end.difference(DateTime.now());
    if (r.isNegative) return 'Sleep';
    final totalMin = r.inMinutes;
    if (totalMin < 1) return '< 1m';
    if (totalMin < 60) return '${totalMin}m';
    final h = totalMin ~/ 60;
    final m = totalMin.remainder(60);
    return m > 0 ? '${h}h ${m}m' : '${h}h';
  }

  @override
  Widget build(BuildContext context) {
    return _ActionButton(
      label: _label(),
      icon: Icons.bedtime_outlined,
      active: widget.timerEnd != null,
      semanticLabel:
          widget.timerEnd != null ? 'Sleep timer: active' : 'Set sleep timer',
      onTap: widget.onTap,
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final String? semanticLabel;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.active = false,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? SagaColors.accent : SagaColors.fgMuted;
    return Semantics(
      label: semanticLabel ?? label,
      button: true,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(color: color, fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Cast sheet ────────────────────────────────────────────────────────────────

class _CastSheet extends ConsumerWidget {
  final AudioPlayerService service;
  const _CastSheet({required this.service});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final castService = ref.watch(castServiceProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Cast to device',
              style: TextStyle(
                  color: SagaColors.fg,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          StreamBuilder<CastState>(
            stream: castService.stateStream,
            initialData: castService.state,
            builder: (context, snap) {
              final state = snap.data ?? CastState.idle;

              if (state == CastState.connected) {
                return Column(
                  children: [
                    ListTile(
                      leading:
                          Icon(Icons.cast_connected, color: SagaColors.accent),
                      title: Text('Casting audio',
                          style: TextStyle(color: SagaColors.fg)),
                      subtitle: Text('Audio is playing on the Cast device',
                          style: TextStyle(
                              color: SagaColors.fgSubtle, fontSize: 12)),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await castService.stopCasting();
                          if (context.mounted) Navigator.pop(context);
                        },
                        icon: const Icon(Icons.cast_outlined),
                        label: const Text('Disconnect'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: const BorderSide(color: Colors.redAccent),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                );
              }

              if (state == CastState.connecting) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: AnimatedSagaMark(size: 36, state: SagaMarkState.buffering)),
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Select a Chromecast or Google Cast device on your local network.',
                    style: TextStyle(color: SagaColors.fgMuted, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        Navigator.pop(context);
                        await castService.openDevicePicker();
                      },
                      icon: const Icon(Icons.cast),
                      label: const Text('Choose device'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: SagaColors.accent,
                        foregroundColor: SagaColors.accentFg,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── M4B chapter list ──────────────────────────────────────────────────────────

class _M4bChapterList extends StatelessWidget {
  final List<M4bChapter> chapters;
  final AudioPlayerService service;
  final ScrollController scrollController;

  const _M4bChapterList({
    required this.chapters,
    required this.service,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: service.positionStream,
      builder: (context, snap) {
        final pos = snap.data ?? Duration.zero;
        final activeIdx = _activeIndex(pos);
        return ListView.builder(
          controller: scrollController,
          itemCount: chapters.length,
          itemBuilder: (context, i) {
            final chapter = chapters[i];
            final isActive = i == activeIdx;
            return ListTile(
              leading: isActive
                  ? Icon(Icons.play_arrow_rounded, color: SagaColors.accent)
                  : Text('${i + 1}',
                      style: TextStyle(
                          color: SagaColors.fgSubtle, fontSize: 13)),
              title: Text(
                chapter.title,
                style: TextStyle(
                  color: isActive ? SagaColors.accent : SagaColors.fg,
                  fontSize: 14,
                  fontWeight:
                      isActive ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              trailing: Text(
                fmtDuration(chapter.start),
                style: TextStyle(color: SagaColors.fgSubtle, fontSize: 12),
              ),
              onTap: () {
                service.seek(chapter.start);
                Navigator.pop(context);
              },
            );
          },
        );
      },
    );
  }

  int _activeIndex(Duration pos) {
    for (int i = chapters.length - 1; i >= 0; i--) {
      if (pos >= chapters[i].start) return i;
    }
    return 0;
  }

}

// ── Plex track list ───────────────────────────────────────────────────────────

class _PlexTrackList extends StatelessWidget {
  final List<PlexTrack> tracks;
  final int currentIdx;
  final AudioPlayerService service;
  final ScrollController scrollController;

  const _PlexTrackList({
    required this.tracks,
    required this.currentIdx,
    required this.service,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: scrollController,
      itemCount: tracks.length,
      itemBuilder: (context, i) {
        final track = tracks[i];
        final isActive = i == currentIdx;
        return ListTile(
          leading: isActive
              ? Icon(Icons.play_arrow_rounded, color: SagaColors.accent)
              : Text('${i + 1}',
                  style:
                      TextStyle(color: SagaColors.fgSubtle, fontSize: 13)),
          title: Text(
            track.title,
            style: TextStyle(
              color: isActive ? SagaColors.accent : SagaColors.fg,
              fontSize: 14,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          trailing: Text(
            fmtDuration(Duration(milliseconds: track.durationMs)),
            style: TextStyle(color: SagaColors.fgSubtle, fontSize: 12),
          ),
          onTap: () {
            service.skipToQueueItem(i);
            Navigator.pop(context);
          },
        );
      },
    );
  }

}

// ── Finished panel (replaces the cover when a book completes) ──────────────────

class _FinishedPanel extends ConsumerWidget {
  final AudioPlayerService service;
  final String bookKey;
  const _FinishedPanel({required this.service, required this.bookKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = CompletedBooksStore.completionCount(bookKey);
    final days = ListenDaysStore.daysListened(bookKey);
    final start = ListenDaysStore.startDate(bookKey);
    final dates = CompletedBooksStore.completionDates(bookKey);
    final finished = dates.isEmpty ? null : dates.last;
    final spanDays = (start != null && finished != null)
        ? finished.difference(start).inDays + 1
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
              onPressed: () => service.justFinishedBook.value = null,
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
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _playNext(ref, book),
            icon: const Icon(Icons.skip_next_rounded, size: 20),
            label: Text(
              book.title,
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
      ],
    );
  }

  Future<void> _playNext(WidgetRef ref, PlexBook book) async {
    try {
      final tracks = await ref.read(tracksProvider(book.ratingKey).future);
      final savedSpeed = SettingsStore.getBookSpeed(book.ratingKey);
      await service.loadBook(bookRatingKey: book.ratingKey, tracks: tracks);
      await service.setSpeed(savedSpeed);
      ref.read(playbackSpeedProvider.notifier).state = savedSpeed;
      await service.play();
    } catch (_) {}
  }
}
