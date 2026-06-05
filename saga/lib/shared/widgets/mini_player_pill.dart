import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import '../../core/theme/saga_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'saga_mark.dart' show AnimatedSagaMark, SagaMarkState;

import '../../core/audio/m4b_chapter_reader.dart';
import '../../core/plex/plex_client.dart';
import '../../core/providers.dart';
import '../../features/player/player_screen.dart';
import '../../features/player/player_service.dart';

class MiniPlayerPill extends ConsumerWidget {
  final AudioPlayerService service;
  final MediaItem mediaItem;

  const MiniPlayerPill({
    super.key,
    required this.service,
    required this.mediaItem,
  });

  String? _buildM4bParam() {
    final tracks = service.currentTracks;
    if (tracks.length != 1) return null;
    return PlexClient.instance.resolveM4bParam(tracks[0]);
  }

  String _activeChapter(List<M4bChapter> chapters, Duration pos) {
    for (int i = chapters.length - 1; i >= 0; i--) {
      if (pos >= chapters[i].start) return chapters[i].title;
    }
    return chapters.first.title;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final param = _buildM4bParam();
    final chapters = param != null
        ? ref.watch(m4bChaptersProvider(param)).valueOrNull ?? const <M4bChapter>[]
        : const <M4bChapter>[];

    return StreamBuilder<PlaybackState>(
      stream: service.playbackState,
      builder: (context, snap) {
        final playing = snap.data?.playing ?? false;
        final loading =
            snap.data?.processingState == AudioProcessingState.loading ||
            snap.data?.processingState == AudioProcessingState.buffering;

        // If we have embedded chapters, also stream position to get current chapter name
        if (chapters.isNotEmpty) {
          return StreamBuilder<Duration>(
            stream: service.positionStream,
            builder: (context, posSnap) {
              final chapterTitle =
                  _activeChapter(chapters, posSnap.data ?? Duration.zero);
              return _buildPill(
                  context, playing, loading, mediaItem.album ?? mediaItem.title, chapterTitle);
            },
          );
        }

        return _buildPill(
            context, playing, loading, mediaItem.album ?? mediaItem.title, mediaItem.title);
      },
    );
  }

  Widget _buildPill(BuildContext context, bool playing, bool loading,
      String title, String? subtitle) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Material(
        color: SagaColors.surface,
        borderRadius: BorderRadius.circular(30),
        elevation: 8,
        shadowColor: Colors.black54,
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PlayerScreen()),
          ),
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                // Album art
                ClipRRect(
                  borderRadius:
                      const BorderRadius.horizontal(left: Radius.circular(30)),
                  child: SizedBox(
                    width: 64,
                    height: 64,
                    child: mediaItem.artUri != null
                        ? _artwork(mediaItem.artUri!)
                        : _artPlaceholder(),
                  ),
                ),
                const SizedBox(width: 12),
                // Track / chapter info
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: SagaColors.fg,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle,
                          style: TextStyle(
                              color: SagaColors.fgMuted, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                // Controls
                GestureDetector(
                  onTap: loading ? null : () => playing ? service.pause() : service.play(),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: AnimatedSagaMark(
                      size: 26,
                      state: loading
                          ? SagaMarkState.buffering
                          : playing
                              ? SagaMarkState.playing
                              : SagaMarkState.paused,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.skip_next_rounded,
                      color: SagaColors.fgMuted, size: 24),
                  onPressed: service.skipToNext,
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _artwork(Uri uri) {
    if (uri.scheme == 'file') {
      return Image.file(
        File(uri.toFilePath()),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _artPlaceholder(),
      );
    }
    return Image.network(
      uri.toString(),
      fit: BoxFit.cover,
      cacheWidth: 160,
      frameBuilder: (_, child, frame, syncLoad) {
        if (syncLoad || frame != null) return child;
        return _artPlaceholder();
      },
      errorBuilder: (_, _, _) => _artPlaceholder(),
    );
  }

  Widget _artPlaceholder() => Container(
        color: SagaColors.surfaceAlt,
        child: Icon(Icons.book, color: SagaColors.fgSubtle, size: 28),
      );
}
