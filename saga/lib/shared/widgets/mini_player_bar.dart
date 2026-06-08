import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import '../../core/theme/saga_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/player/player_provider.dart';
import '../../features/player/player_screen.dart';
import '../widgets/saga_mark.dart' show AnimatedSagaMark, SagaMarkState;

class MiniPlayerBar extends ConsumerWidget {
  const MiniPlayerBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(playerServiceProvider);

    return StreamBuilder<MediaItem?>(
      stream: service.mediaItem,
      builder: (context, itemSnap) {
        final item = itemSnap.data;
        if (item == null) return const SizedBox.shrink();

        return StreamBuilder<PlaybackState>(
          stream: service.playbackState,
          builder: (context, stateSnap) {
            final playing = stateSnap.data?.playing ?? false;
            final loading =
                stateSnap.data?.processingState == AudioProcessingState.loading ||
                stateSnap.data?.processingState == AudioProcessingState.buffering;

            return Material(
              color: SagaColors.surface,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Divider(height: 1, thickness: 1, color: SagaColors.surfaceAlt),
                  InkWell(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const PlayerScreen()),
                    ),
                    child: SafeArea(
                      top: false,
                      child: SizedBox(
                        height: 68,
                        child: Row(
                          children: [
                            _ArtThumbnail(artUri: item.artUri, title: item.title),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.title,
                                    style: TextStyle(
                                      color: SagaColors.fg,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (item.album != null)
                                    Text(
                                      item.album!,
                                      style: TextStyle(
                                        color: SagaColors.fgMuted,
                                        fontSize: 12,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
                            Semantics(
                              label: playing ? 'Pause' : 'Play',
                              button: true,
                              excludeSemantics: true,
                              child: GestureDetector(
                                onTap: () =>
                                    playing ? service.pause() : service.play(),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12),
                                  child: AnimatedSagaMark(
                                    size: 32,
                                    state: loading
                                        ? SagaMarkState.buffering
                                        : playing
                                            ? SagaMarkState.playing
                                            : SagaMarkState.paused,
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.skip_next,
                                  color: SagaColors.fgMuted, size: 24),
                              onPressed: () => service.skipToNext(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _ArtThumbnail extends StatelessWidget {
  final Uri? artUri;
  final String title;
  const _ArtThumbnail({this.artUri, required this.title});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 68,
      child: artUri != null ? _buildImage(artUri!) : _placeholder(),
    );
  }

  Widget _buildImage(Uri uri) {
    final image = uri.scheme == 'file'
        ? Image.file(
            File(uri.toFilePath()),
            fit: BoxFit.cover,
            cacheWidth: 112,
            errorBuilder: (_, _, _) => _placeholder(),
          )
        : Image.network(
            uri.toString(),
            fit: BoxFit.cover,
            cacheWidth: 112,
            frameBuilder: (_, child, frame, syncLoad) {
              if (syncLoad || frame != null) return child;
              return _placeholder();
            },
            errorBuilder: (_, _, _) => _placeholder(),
          );
    return Semantics(
      label: '$title cover art',
      excludeSemantics: true,
      child: image,
    );
  }

  Widget _placeholder() => Container(
        color: SagaColors.surfaceAlt,
        child: Icon(Icons.book, color: SagaColors.fgSubtle, size: 24),
      );
}
