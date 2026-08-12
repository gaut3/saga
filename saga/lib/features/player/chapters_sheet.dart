import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/m4b_chapter_reader.dart';
import '../../core/plex/models/plex_track.dart';
import '../../core/providers.dart';
import '../../core/theme/saga_theme.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/saga_mark.dart' show AnimatedSagaMark, SagaMarkState;
import '../../shared/widgets/saga_sheet.dart';
import 'player_service.dart';
import 'track_position_math.dart';

void showChaptersSheet(BuildContext context,
    {required AudioPlayerService service, String? m4bKey}) {
  final tracks = service.currentTracks;

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
              const SagaSheetHandle(),
              SagaSheetTitle('Chapters'),
              if (m4bAsync.isLoading)
                Padding(
                  padding: const EdgeInsets.all(24),
                  // The mark's CustomPaint is semantically silent; without the
                  // label TalkBack gets no hint the list is still loading.
                  child: Semantics(
                    label: 'Loading chapters',
                    child: const AnimatedSagaMark(
                        size: 36, state: SagaMarkState.buffering),
                  ),
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
                        service: service,
                        scrollController: scrollController,
                      ),
              ),
            ],
          ),
        );
      },
    ),
    // DraggableScrollableSheet manages its own column; the handle is
    // rendered inside it instead of by showSagaSheet's wrapper.
    showHandle: false,
  );
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
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
          itemCount: chapters.length,
          itemBuilder: (context, i) {
            final chapter = chapters[i];
            final isActive = i == activeIdx;
            return ListTile(
              // Announced as "selected" — the play arrow is the only visual
              // cue and carries no label of its own.
              selected: isActive,
              leading: isActive
                  ? Icon(Icons.play_arrow_rounded, color: SagaColors.accent)
                  : Text('${i + 1}',
                      style: TextStyle(
                          color: SagaColors.fgSubtle, fontSize: 13)),
              title: Text(
                chapter.title,
                style: TextStyle(
                  color: isActive ? SagaColors.accentText : SagaColors.fg,
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

  int _activeIndex(Duration pos) => chapterIndexAt(
      [for (final c in chapters) c.start.inMilliseconds], pos.inMilliseconds);

}

// ── Plex track list ───────────────────────────────────────────────────────────

class _PlexTrackList extends StatelessWidget {
  final List<PlexTrack> tracks;
  final AudioPlayerService service;
  final ScrollController scrollController;

  const _PlexTrackList({
    required this.tracks,
    required this.service,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    // Live, like the M4B list beside it: the index captured at sheet-open
    // left the play arrow on the previous chapter when playback rolled over
    // to the next file while the sheet was up.
    return StreamBuilder<int?>(
      stream: service.currentIndexStream,
      initialData: service.player.currentIndex,
      builder: (context, idxSnap) {
        final currentIdx = idxSnap.data ?? 0;
        return ListView.builder(
          controller: scrollController,
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
          itemCount: tracks.length,
          itemBuilder: (context, i) {
            final track = tracks[i];
            final isActive = i == currentIdx;
            return ListTile(
              selected: isActive,
              leading: isActive
                  ? Icon(Icons.play_arrow_rounded, color: SagaColors.accent)
                  : Text('${i + 1}',
                      style:
                          TextStyle(color: SagaColors.fgSubtle, fontSize: 13)),
              title: Text(
                track.title,
                style: TextStyle(
                  color: isActive ? SagaColors.accentText : SagaColors.fg,
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
      },
    );
  }
}
