import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/plex/plex_client.dart';
import '../../core/theme/saga_theme.dart';

/// Book cover image backed by Flutter's in-memory ImageCache.
///
/// Uses Image.network with cacheWidth so that cache hits are synchronous —
/// navigating back to a list never shows the placeholder for images already
/// loaded this session.
///
/// On network error the widget auto-retries up to [_maxRetries] times with a
/// short back-off delay. Only after all retries fail does it show a refresh
/// icon (tap to retry from the beginning).
class BookCoverImage extends StatefulWidget {
  final String? thumbPath;
  final int cacheWidth;
  final BoxFit fit;
  /// Accessible label for screen readers. Pass the book title + " cover art".
  /// Omit (or pass null) for purely decorative uses — the image is then
  /// excluded from the semantics tree.
  final String? semanticLabel;

  /// Fill a non-square box without cropping the artwork: a blurred, cropped
  /// copy fills the box behind a dimming scrim, with the whole cover contained
  /// on top. Use wherever the box isn't square — `BoxFit.cover` there silently
  /// eats the top/bottom (or sides) of covers that are.
  ///
  /// Overrides [fit]. Leave off for square boxes; plain cover is cheaper.
  final bool letterboxed;

  const BookCoverImage({
    super.key,
    required this.thumbPath,
    this.cacheWidth = 200,
    this.fit = BoxFit.cover,
    this.semanticLabel,
    this.letterboxed = false,
  });

  @override
  State<BookCoverImage> createState() => _BookCoverImageState();
}

class _BookCoverImageState extends State<BookCoverImage> {
  static const _maxRetries = 3;
  static const _retryDelay = Duration(seconds: 2);

  int _attempt = 0;
  Timer? _retryTimer;

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  void _scheduleRetry() {
    if (_attempt >= _maxRetries) return;
    _retryTimer?.cancel();
    _retryTimer = Timer(_retryDelay, () {
      if (mounted) setState(() => _attempt++);
    });
  }

  @override
  Widget build(BuildContext context) {
    final url =
        PlexClient.instance.buildArtUri(widget.thumbPath)?.toString();
    if (url == null) return _placeholder();

    return Semantics(
      label: widget.semanticLabel,
      excludeSemantics: widget.semanticLabel == null,
      child: CachedNetworkImage(
        key: ValueKey('$url-$_attempt'),
        imageUrl: url,
        fit: widget.fit,
        memCacheWidth: widget.cacheWidth,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        // One download, one cache entry — the letterbox draws it twice.
        imageBuilder: widget.letterboxed ? _buildLetterbox : null,
        placeholder: (_, _) => _placeholder(),
        errorWidget: (_, _, _) {
          if (_attempt < _maxRetries) {
            _scheduleRetry();
            return _placeholder();
          }
          return GestureDetector(
            onTap: () => setState(() => _attempt = 0),
            child: _errorPlaceholder(),
          );
        },
      ),
    );
  }

  /// Blurred cropped backdrop + scrim + contained artwork. Same treatment the
  /// player screen uses for its hero cover, so letterboxed covers read the same
  /// everywhere.
  Widget _buildLetterbox(BuildContext context, ImageProvider provider) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Scale the blur to the box: a sigma tuned for a full-screen cover
        // flattens a 180 px tile to a single colour.
        final shortest = constraints.biggest.shortestSide;
        final sigma =
            shortest.isFinite ? (shortest / 12).clamp(6.0, 28.0) : 28.0;
        return Stack(
          fit: StackFit.expand,
          children: [
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
              child: Image(image: provider, fit: BoxFit.cover),
            ),
            ColoredBox(color: Colors.black.withValues(alpha: 0.30)),
            Image(image: provider, fit: BoxFit.contain),
          ],
        );
      },
    );
  }

  Widget _placeholder() => Container(
        alignment: Alignment.center,
        color: SagaColors.surfaceAlt,
        child: Icon(Icons.book, color: SagaColors.fgSubtle, size: 32),
      );

  Widget _errorPlaceholder() => Container(
        alignment: Alignment.center,
        color: SagaColors.surfaceAlt,
        child: Icon(Icons.refresh, color: SagaColors.fgSubtle, size: 28),
      );
}
