import 'dart:async';
import 'dart:io' show File;
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/plex/plex_client.dart';
import '../../core/storage/artwork_cache.dart';
import '../../core/theme/saga_theme.dart';

/// Shared decode widths for covers.
///
/// Flutter's in-memory ImageCache keys a decoded image by URL *and* decode
/// size, so every distinct [BookCoverImage.cacheWidth] is a separate decode: a
/// cover already on screen in a strip warmed nothing for the Home hero card,
/// which decoded the same file again — visibly, as a placeholder flash when
/// returning from the player. Eleven ad-hoc widths collapsed into these three
/// buckets, so any surface that has shown a cover warms every other surface in
/// its bucket.
const kCoverCacheWidthThumb = 160; // pills, list rows, small tiles
const kCoverCacheWidthCard = 320; // book cards (strips/grids), Home hero
const kCoverCacheWidthDetail = 400; // book-detail header, collection tiles

/// Book cover image, local copy first.
///
/// [ArtworkCache] when the phone already holds the file, otherwise
/// `CachedNetworkImage` with the token in a header (never the URL — the
/// on-disk cache keys by URL, which is how every cover once wrote a live token
/// to an unencrypted database).
///
/// A memory-cache hit renders synchronously. A miss (first decode this
/// session at this size) re-decodes from the disk cache in well under
/// [_placeholderDelay], so the placeholder fades in late enough that only a
/// genuine network fetch ever shows it.
///
/// On network error the widget auto-retries up to [_maxRetries] times with a
/// short back-off delay. Only after all retries fail does it show a refresh
/// icon (tap to retry from the beginning).
class BookCoverImage extends StatefulWidget {
  final String? thumbPath;
  final int cacheWidth;

  /// Accessible label for screen readers. Pass the book title + " cover art".
  /// Omit (or pass null) for purely decorative uses — the image is then
  /// excluded from the semantics tree.
  final String? semanticLabel;

  /// Fill a non-square box without cropping the artwork: a blurred, cropped
  /// copy fills the box behind a dimming scrim, with the whole cover contained
  /// on top. Use wherever the box isn't square — `BoxFit.cover` there silently
  /// eats the top/bottom (or sides) of covers that are.
  ///
  /// Leave off for square boxes; plain cover is cheaper.
  final bool letterboxed;

  const BookCoverImage({
    super.key,
    required this.thumbPath,
    this.cacheWidth = kCoverCacheWidthCard,
    this.semanticLabel,
    this.letterboxed = false,
  });

  @override
  State<BookCoverImage> createState() => _BookCoverImageState();
}

class _BookCoverImageState extends State<BookCoverImage> {
  static const _maxRetries = 3;
  static const _retryDelay = Duration(seconds: 2);

  /// How long a load has before the placeholder becomes visible. A re-decode
  /// from the disk cache finishes inside this, so covers the phone already has
  /// never flash grey; a real network fetch fades the placeholder in instead
  /// of popping it.
  static const _placeholderDelay = Duration(milliseconds: 250);

  int _attempt = 0;
  Timer? _retryTimer;

  /// The cover already on disk, if there is one.
  ///
  /// Resolved here rather than in `build` because the lookup stats a file, and
  /// a scrolling grid rebuilds every visible card every frame.
  Uri? _localUri;

  @override
  void initState() {
    super.initState();
    _localUri = ArtworkCache.getLocalUri(widget.thumbPath);
  }

  @override
  void didUpdateWidget(BookCoverImage old) {
    super.didUpdateWidget(old);
    if (old.thumbPath != widget.thumbPath) {
      _localUri = ArtworkCache.getLocalUri(widget.thumbPath);
    }
  }

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
    return Semantics(
      label: widget.semanticLabel,
      excludeSemantics: widget.semanticLabel == null,
      child: _localUri != null ? _fromFile(_localUri!) : _fromNetwork(),
    );
  }

  /// The copy already on this phone.
  ///
  /// [ArtworkCache] is written for every book the player loads, and it is what
  /// the lock screen, Android Auto and the mini player have always drawn from —
  /// which is why those kept showing covers offline while the app's own lists
  /// went grey: everything else here asked the server for a file it already
  /// had. Reading it costs no request and no cache-validity check, so it is the
  /// faster path online too.
  Widget _fromFile(Uri uri) {
    final provider = ResizeImage(
      FileImage(File(uri.toFilePath())),
      width: widget.cacheWidth,
    );
    if (widget.letterboxed) return _buildLetterbox(context, provider);
    return Image(
      image: provider,
      fit: BoxFit.cover,
      // The file was there when this widget was built and could have been
      // pruned since. Fall back to the placeholder rather than a broken box.
      errorBuilder: (_, _, _) => _placeholder(),
    );
  }

  Widget _fromNetwork() {
    // Token in a header, never in the URL: CachedNetworkImage keys its on-disk
    // cache by URL, so a token in the query string ends up written to an
    // unencrypted database and left there after sign-out.
    final url = PlexClient.instance.buildThumbUrl(widget.thumbPath);
    if (url == null) return _placeholder();

    return CachedNetworkImage(
      key: ValueKey('$url-$_attempt'),
      imageUrl: url,
      httpHeaders: PlexClient.instance.authHeaders,
      fit: BoxFit.cover,
      memCacheWidth: widget.cacheWidth,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      placeholderFadeInDuration: _placeholderDelay,
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
        final sigma = shortest.isFinite
            ? (shortest / 12).clamp(6.0, 28.0)
            : 28.0;
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

/// Full-size cover stand-in: surface + centred book glyph. The player and
/// book-detail hero covers use it when no artwork resolves; they carried
/// byte-identical private copies before.
class CoverPlaceholder extends StatelessWidget {
  const CoverPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: SagaColors.surface,
      child: Center(
        child: Icon(Icons.book, size: 80, color: SagaColors.fgSubtle),
      ),
    );
  }
}
