import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import '../../core/theme/saga_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/m4b_chapter_reader.dart';
import '../../core/book_progress.dart';
import '../../core/plex/models/plex_book.dart';
import '../library/book_detail_screen.dart';
import '../../core/plex/models/plex_track.dart';
import '../../core/storage/bookmark_store.dart';
import '../../core/storage/settings_store.dart';
import '../../core/providers.dart';
import '../../core/storage/named_bookmark_store.dart';
import '../../core/storage/playback_log_store.dart';
import '../../core/plex/plex_client.dart';
import '../../core/utils/format.dart';
import '../../core/utils/text_measure.dart';
import '../library/effective_chapter_count.dart';
import '../../shared/widgets/book_cover_image.dart' show CoverPlaceholder;
import '../../shared/widgets/meta_chip.dart';
import '../../shared/widgets/saga_mark.dart' show AnimatedSagaMark, SagaMarkState;
import '../../shared/widgets/saga_toast.dart';
import 'bookmark_edit_sheet.dart';
import 'cast_sheet.dart';
import 'chapters_sheet.dart';
import 'finished_panel.dart';
import 'player_provider.dart';
import 'player_service.dart';
import 'sessions_sheet.dart';
import 'sleep_speed_sheets.dart';

class PlayerScreen extends ConsumerWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(playerServiceProvider);
    final libraryKey = ref.watch(activeLibraryKeyProvider).valueOrNull;
    final books = libraryKey != null
        ? ref.watch(booksProvider(libraryKey)).valueOrNull
        : null;

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

          // Resolved here, not in the enclosing build: every screen that opens
          // the player pushes the route *before* awaiting loadBook, so at the
          // first build the service still holds the previous book (or none).
          // The media item is what changes when the book does, so reading the
          // key alongside it is what keeps the two describing the same book.
          final bookKey = service.currentBookRatingKey;
          PlexBook? currentBook;
          try {
            if (books != null && bookKey != null) {
              currentBook = books.firstWhere((b) => b.ratingKey == bookKey);
            }
          } catch (_) {}

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TopPills(service: service, bookKey: bookKey),
              Expanded(
                child: ValueListenableBuilder<String?>(
                  valueListenable: service.justFinishedBook,
                  builder: (context, finishedKey, _) {
                    if (finishedKey != null && finishedKey == bookKey) {
                      return FinishedPanel(
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
                            child: _RevealCover(
                              artUri: item?.artUri,
                              book: currentBook,
                              onFullDetails: currentBook != null
                                  ? () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) => BookDetailScreen(
                                                book: currentBook!)),
                                      )
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              _TrackInfo(
                item: item,
                onBookTap: currentBook != null
                    ? () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  BookDetailScreen(book: currentBook!)),
                        )
                    : null,
              ),
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
              onTap: () =>
                  showChaptersSheet(context, service: service, m4bKey: param),
            ),
            const SizedBox(width: 8),
          ],
          _PillButton(
            icon: Icons.bookmarks_outlined,
            label: bookmarkCount > 0
                ? 'Bookmarks ($bookmarkCount)'
                : 'Bookmarks',
            onTap: () {
              if (bookKey != null) {
                showBookmarksListSheet(context, ref, bookKey!,
                    service: service);
              }
            },
          ),
          if (sessionCount > 0) ...[
            const SizedBox(width: 8),
            _PillButton(
              icon: Icons.history_rounded,
              label: 'Sessions ($sessionCount)',
              onTap: () {
                if (bookKey != null) showSessionsSheet(context, bookKey!);
              },
            ),
          ],
        ],
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


// ── Cover art ─────────────────────────────────────────────────────────────────

/// The cover art, which defocuses to reveal the book's detail through it.
///
/// Not a flip. A flip is a rigid-body rotation of a physical card, and nothing
/// else in Saga rotates or has a back side — the app's motion vocabulary is
/// light: blur, opacity, desaturation, gradient masks. A flip also destroys the
/// artwork mid-turn, and that artwork is the source of the whole screen's colour
/// field. So the cover stays exactly where it is and goes *out of focus* while
/// the text surfaces through it, which makes the ambient glow the mechanism of
/// the transition rather than something to protect from it.
///
/// Deliberately a *peek*: it never navigates, the same tap reverses it, and the
/// blurb is truncated under a fade rather than made scrollable. Going deep is
/// the title row's job ([BookDetailScreen]), which the revealed face also links
/// to — two affordances at clearly different depths.
class _RevealCover extends ConsumerStatefulWidget {
  final Uri? artUri;
  final PlexBook? book;
  final VoidCallback? onFullDetails;

  const _RevealCover({this.artUri, this.book, this.onFullDetails});

  @override
  ConsumerState<_RevealCover> createState() => _RevealCoverState();
}

class _RevealCoverState extends ConsumerState<_RevealCover>
    with SingleTickerProviderStateMixin {
  /// Out is a touch slower than back: revealing is the deliberate act, and
  /// dismissing should get out of the way.
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
    reverseDuration: const Duration(milliseconds: 260),
  );

  /// The artwork's own recession.
  late final Animation<double> _defocus =
      CurvedAnimation(parent: _reveal, curve: Curves.easeOutCubic);

  /// Chips lead, summary follows ~60 ms later — the stagger reads as text
  /// rising through the cover rather than being switched on.
  late final Animation<double> _chips = CurvedAnimation(
      parent: _reveal, curve: const Interval(0.40, 0.90, curve: Curves.easeOut));
  late final Animation<double> _blurb = CurvedAnimation(
      parent: _reveal, curve: const Interval(0.57, 1.0, curve: Curves.easeOut));

  static const _maxBlurSigma = 40.0;

  @override
  void initState() {
    super.initState();
    // The Semantics label sits outside the AnimatedBuilder, so it needs a nudge
    // to stop announcing the state we just left.
    _reveal.addStatusListener((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant _RevealCover old) {
    super.didUpdateWidget(old);
    // A new book (auto-advance, or the user starting another) should show its
    // cover, not the detail of a book they never opened.
    if (old.book?.ratingKey != widget.book?.ratingKey) _reveal.value = 0;
  }

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  // A plain field, not `_reveal.value > 0.5`: the semantic label below reads
  // it in build, which doesn't re-run during the animation — derived from the
  // controller it stayed on the pre-toggle action for the life of the route.
  bool _detailsShown = false;

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  void _toggle() {
    setState(() => _detailsShown = !_detailsShown);
    if (_reduceMotion) {
      // No tween at all — land on the end state.
      _reveal.value = _detailsShown ? 1 : 0;
      return;
    }
    _detailsShown ? _reveal.forward() : _reveal.reverse();
  }

  ImageProvider? get _provider {
    final uri = widget.artUri;
    if (uri == null) return null;
    // Cap the decode: 900 px covers a full-width hero on a 3× screen, where an
    // uncapped FileImage decodes whatever the file holds — a 3000×3000 cover
    // is ~36 MB decoded, enough to evict every list thumbnail behind this
    // screen and greet the pop with a row of placeholders.
    return uri.scheme == 'file'
        ? ResizeImage(FileImage(File(uri.toFilePath())), width: 900)
        : ResizeImage(NetworkImage(uri.toString()), width: 600);
  }

  @override
  Widget build(BuildContext context) {
    final provider = _provider;
    // Nothing to reveal without the book record.
    final canReveal = widget.book != null;

    return GestureDetector(
      onTap: canReveal ? _toggle : null,
      child: Semantics(
        button: canReveal,
        label: canReveal
            ? (_detailsShown ? 'Show cover' : 'Show book details')
            : null,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AnimatedBuilder(
            animation: _reveal,
            // The glow is expensive (a full-size blur) and doesn't change
            // during the reveal, so it's built once and rasterised once rather
            // than re-filtered on all 60 frames alongside the artwork's own
            // animating blur.
            child: RepaintBoundary(child: _glow(provider)),
            builder: (context, glow) =>
                _buildLayers(provider, canReveal, glow!),
          ),
        ),
      ),
    );
  }

  /// The ambient glow: the artwork blurred to fill the square. Static across
  /// the reveal, so it's hoisted out of the per-frame rebuild.
  Widget _glow(ImageProvider? provider) => provider != null
      ? ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Image(
            image: provider,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => ColoredBox(color: SagaColors.surface),
          ),
        )
      : ColoredBox(color: SagaColors.surface);

  Widget _buildLayers(ImageProvider? provider, bool canReveal, Widget glow) {
    final t = _defocus.value;
    final sigma = t * _maxBlurSigma;
    final saturation = 1.0 - t * (1.0 - SagaColors.coverRevealSaturation);

    Widget artwork = provider != null
        ? Image(
            image: provider,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const CoverPlaceholder(),
          )
        : const CoverPlaceholder();
    if (t > 0) {
      artwork = ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: ColorFiltered(
          colorFilter: ColorFilter.matrix(_saturationMatrix(saturation)),
          child: Opacity(opacity: 1.0 - 0.65 * t, child: artwork),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // The glow, derived from the art. It never stops being painted, and it
        // comes *forward* as the artwork recedes: the scrim over it lightens by
        // ~0.1, so light fills the space the detail vacates.
        glow,
        ColoredBox(color: Colors.black.withValues(alpha: 0.30 - 0.10 * t)),
        artwork,
        // Theme scrim, so the blurb has something to sit on however pale the
        // cover is. Per-theme: light themes need much more of it.
        if (t > 0)
          ColoredBox(
            color:
                SagaColors.bg.withValues(alpha: t * SagaColors.coverRevealScrim),
          ),
        if (t > 0 && widget.book != null)
          IgnorePointer(
            ignoring: t < 0.5,
            child: _CoverDetail(
              book: widget.book!,
              onFullDetails: widget.onFullDetails,
              chips: _chips,
              blurb: _blurb,
            ),
          ),
        // Anchored cue: the cover never moves, so this stays put and simply
        // crossfades from "there's more here" to "close".
        if (canReveal)
          Positioned(
            right: 10,
            bottom: 10,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                shape: BoxShape.circle,
              ),
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Opacity(
                      opacity: 1 - t,
                      child: Icon(Icons.info_outline_rounded,
                          size: 16,
                          color: Colors.white.withValues(alpha: 0.9)),
                    ),
                    Opacity(
                      opacity: t,
                      child: Icon(Icons.close_rounded,
                          size: 16,
                          color: Colors.white.withValues(alpha: 0.9)),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Saturation as a colour matrix. 1 = untouched, 0 = greyscale.
List<double> _saturationMatrix(double s) {
  // Rec. 709 luminance weights.
  const r = 0.2126, g = 0.7152, b = 0.0722;
  final inv = 1 - s;
  return <double>[
    inv * r + s, inv * g, inv * b, 0, 0, //
    inv * r, inv * g + s, inv * b, 0, 0, //
    inv * r, inv * g, inv * b + s, 0, 0, //
    0, 0, 0, 1, 0, //
  ];
}

/// The detail that surfaces through the defocused cover: a blurb, not a
/// document.
///
/// Carries no background of its own — the theme scrim behind it belongs to the
/// reveal, so the two fade together. The summary is truncated under a fade
/// rather than made scrollable: a small scroller inside a transitioning surface
/// feels bad and buries text behind a gesture nobody tries. "Full details" is
/// the way to the rest.
class _CoverDetail extends ConsumerWidget {
  final PlexBook book;
  final VoidCallback? onFullDetails;

  /// Staggered entries, driven by the reveal — chips first, then the blurb.
  final Animation<double> chips;
  final Animation<double> blurb;

  const _CoverDetail({
    required this.book,
    required this.chips,
    required this.blurb,
    this.onFullDetails,
  });

  /// Fades up with a small lift, so the text reads as rising through the cover.
  Widget _rise(Animation<double> a, Widget child) {
    return AnimatedBuilder(
      animation: a,
      builder: (context, inner) => Opacity(
        opacity: a.value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, 8 * (1 - a.value)),
          child: inner,
        ),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Narrator and genre come from the per-book record, not the listing.
    final book = enrichedBook(ref, this.book);
    final chapters = effectiveChapterCount(ref, book);
    final lengthMs = bookTotalDurationMs(book, BookmarkStore.load(book.ratingKey));
    final summaryStyle =
        TextStyle(color: SagaColors.fgMuted, fontSize: 13, height: 1.45);

    return ShaderMask(
      // Soften both edges so lines don't butt into the square. Same gradient
      // language as the glow layer.
      shaderCallback: (rect) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          Colors.white,
          Colors.white,
          Colors.transparent,
        ],
        stops: [0.0, 0.06, 0.94, 1.0],
      ).createShader(rect),
      blendMode: BlendMode.dstIn,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _rise(
              chips,
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    book.title,
                    style: TextStyle(
                        color: SagaColors.fg,
                        fontSize: 16,
                        fontWeight: FontWeight.w700),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (book.authorName != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      book.authorName!,
                      style:
                          TextStyle(color: SagaColors.accentText, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (book.narratorLabel != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Narrated by ${book.narratorLabel}',
                      style: TextStyle(color: SagaColors.fgMuted, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: bookMetaChips(book,
                        lengthMs: lengthMs, chapterCount: chapters),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _rise(
                blurb,
                (book.summary?.isNotEmpty ?? false)
                    ? _FadedSummary(summary: book.summary!, style: summaryStyle)
                    : Text('No description.',
                        style: TextStyle(
                            color: SagaColors.fgSubtle, fontSize: 13)),
              ),
            ),
            if (onFullDetails != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: onFullDetails,
                  // Default tap-target padding keeps this at the 48 dp floor;
                  // shrinkWrap made it a ~26 dp target.
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Full details',
                          style: TextStyle(
                              color: SagaColors.accentText, fontSize: 13)),
                      Icon(Icons.chevron_right,
                          color: SagaColors.accentText, size: 16),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Summary clipped to the space available, faded out at the bottom when there's
/// more than fits.
class _FadedSummary extends StatelessWidget {
  final String summary;
  final TextStyle style;

  const _FadedSummary({required this.summary, required this.style});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaler = MediaQuery.textScalerOf(context);
        final lineHeight =
            scaler.scale(style.fontSize!) * (style.height ?? 1.0);
        final maxLines =
            (constraints.maxHeight / lineHeight).floor().clamp(1, 999);
        // Measured against the real width — see textOverflows' doc.
        final overflows = textOverflows(
          text: summary,
          style: style,
          maxWidth: constraints.maxWidth,
          maxLines: maxLines,
          textScaler: scaler,
        );
        final text = Text(
          summary,
          style: style,
          maxLines: maxLines,
          // The fade replaces the ellipsis when there's more to read.
          overflow: overflows ? TextOverflow.clip : TextOverflow.ellipsis,
        );
        if (!overflows) return Align(alignment: Alignment.topLeft, child: text);
        return ShaderMask(
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: const [Colors.white, Colors.white, Colors.transparent],
            stops: const [0.0, 0.72, 1.0],
          ).createShader(rect),
          blendMode: BlendMode.dstIn,
          child: Align(alignment: Alignment.topLeft, child: text),
        );
      },
    );
  }
}

// ── Track info ────────────────────────────────────────────────────────────────

class _TrackInfo extends StatelessWidget {
  final MediaItem? item;
  final VoidCallback? onBookTap;
  const _TrackInfo({this.item, this.onBookTap});

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
          GestureDetector(
            onTap: onBookTap,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    item?.album ?? '',
                    style:
                        TextStyle(color: SagaColors.accentText, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (onBookTap != null) ...[
                  const SizedBox(width: 2),
                  Icon(Icons.chevron_right,
                      color: SagaColors.fgSubtle, size: 12),
                ],
              ],
            ),
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

/// Skip-button glyph with the configured interval drawn inside the arc. The
/// material `replay_30`-style icons hardcode their number into the glyph —
/// with 15/45/60 s configured they showed a lying "30" (issue #7), and no
/// numbered variants exist beyond 5/10/30. The plain arc (mirrored for
/// forward) plus a centered label works for any interval.
class _SkipIntervalIcon extends StatelessWidget {
  final int seconds;
  final bool forward;
  final double size;
  final Color color;

  const _SkipIntervalIcon({
    required this.seconds,
    required this.forward,
    required this.size,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.flip(
            flipX: forward,
            child: Icon(Icons.replay_rounded, size: size, color: color),
          ),
          // Slightly below center, matching where the numbered material
          // glyphs place their digits.
          Padding(
            padding: EdgeInsets.only(top: size * 0.14),
            child: Text(
              '$seconds',
              style: TextStyle(
                color: color,
                fontSize: size * 0.32,
                fontWeight: FontWeight.w800,
                height: 1.0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Progress bar — shows book-level progress ──────────────────────────────────

class _ProgressBar extends ConsumerStatefulWidget {
  final AudioPlayerService service;
  const _ProgressBar({required this.service});

  @override
  ConsumerState<_ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends ConsumerState<_ProgressBar> {
  double? _dragValue;
  // The scrub range frozen at drag start. In chapter mode the live range
  // re-anchors itself when playback crosses a chapter boundary — which it
  // can do mid-drag, since audio keeps playing under the held thumb — and
  // releasing at "90%" then seeked to 90% of the *next* chapter.
  ({int startMs, int endMs})? _dragRange;
  // Right-hand label mode: remaining-at-current-speed (default) or book total.
  bool _showTotal = false;

  /// Wall-clock time left in the book at [speed]. The speed is watched rather
  /// than read off the player: this widget otherwise only rebuilds on position
  /// ticks, which stop while paused — so changing speed from the sheet with
  /// playback paused left the countdown showing the old figure.
  Duration _remainingAtSpeed(Duration pos, Duration dur, double speed) {
    final remainingMs = (dur - pos).inMilliseconds.clamp(0, dur.inMilliseconds);
    // Guard nonsense speeds (0 or negative can't occur via the picker, but a
    // division by zero here would take the whole player screen down).
    return Duration(
        milliseconds: speed > 0 ? (remainingMs / speed).round() : remainingMs);
  }

  @override
  Widget build(BuildContext context) {
    final speed = ref.watch(playbackSpeedProvider).valueOrNull ??
        widget.service.player.speed;
    return StreamBuilder<Duration>(
      stream: widget.service.positionStream,
      builder: (context, posSnap) {
        final totalMs = widget.service.totalBookDurationMs;
        final absMs = widget.service.absolutePositionMs;
        // posSnap drives rebuilds; the actual value used is absolutePositionMs.
        posSnap.data;

        // Whole-book range by default; in chapter-scrub mode (Settings →
        // Playback) the slider spans only the current chapter, so very long
        // books can be scrubbed precisely (1 px of a 30 h book ≈ minutes).
        // The range is derived from the live position, so crossing a chapter
        // boundary re-anchors the bar automatically — except mid-drag, where
        // the range frozen at drag start wins (see [_dragRange]).
        final chapterMode = SettingsStore.chapterScrub;
        final range = _dragRange ??
            (chapterMode
                ? widget.service.currentChapterRangeMs()
                : (startMs: 0, endMs: totalMs));
        final rawSpan = range.endMs - range.startMs;
        final spanMs = rawSpan > 0 ? rawSpan : 1;

        final progress = ((absMs - range.startMs) / spanMs).clamp(0.0, 1.0);
        final displayValue = _dragValue ?? progress;
        // Book-level position the thumb currently represents.
        final displayAbsMs = _dragValue != null
            ? range.startMs + (_dragValue! * spanMs).round()
            : absMs;
        // Labels and drag tooltip are chapter-relative in chapter mode so the
        // whole row speaks one unit; book mode is unchanged.
        final displayPos = Duration(
            milliseconds:
                chapterMode ? displayAbsMs - range.startMs : displayAbsMs);
        final displayDur = Duration(
            milliseconds:
                chapterMode ? spanMs : (totalMs > 0 ? totalMs : absMs));

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
                          onChangeStart: (v) => setState(() {
                            _dragRange = range;
                            _dragValue = v;
                          }),
                          onChanged: (v) => setState(() => _dragValue = v),
                          onChangeEnd: (v) {
                            // [range] here is the frozen one — this build ran
                            // with _dragRange set.
                            widget.service.seekAbsolute(Duration(
                                milliseconds:
                                    range.startMs + (v * spanMs).round()));
                            setState(() {
                              _dragValue = null;
                              _dragRange = null;
                            });
                          },
                          // Announced chapter-relative in chapter mode,
                          // matching the visible labels (startMs is 0 and
                          // spanMs the book length in book mode).
                          semanticFormatterCallback: (v) => fmtDuration(
                              Duration(milliseconds: (v * spanMs).round())),
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
                    // Remaining listening time at the current playback speed
                    // (the audiobook convention: 2 h left at 1.5× is really
                    // 1 h 20 m of your evening). Tap to toggle to book total.
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _showTotal = !_showTotal),
                      child: Semantics(
                        label: _showTotal
                            ? (chapterMode ? 'Chapter length' : 'Book length')
                            : 'Time remaining at current speed',
                        button: true,
                        child: Text(
                          _showTotal
                              ? fmtDuration(displayDur)
                              : '-${fmtDuration(_remainingAtSpeed(displayPos, displayDur, speed))}',
                          style: TextStyle(
                              color: SagaColors.fgMuted, fontSize: 12),
                        ),
                      ),
                    ),
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
              icon: _SkipIntervalIcon(
                seconds: SettingsStore.skipBackwardSeconds,
                forward: false,
                size: 28,
                color: SagaColors.fgMuted,
              ),
              color: SagaColors.fgMuted,
              tooltip:
                  'Rewind ${SettingsStore.skipBackwardSeconds} seconds',
              // The service's own handler — the same one the notification and
              // headset buttons hit. This used to be a hand-rolled
              // track-relative seek, so on a multi-file book the on-screen
              // rewind stopped dead at the start of the current file while
              // the notification's crossed into the previous one.
              onPressed: service.rewind,
            ),
            const SizedBox(width: 8),
            // Gesture outside, Semantics inside (like the view toggle in
            // Browse): the other way round, excludeSemantics strips the
            // GestureDetector's tap action and TalkBack gets a button that
            // announces but can't be activated.
            GestureDetector(
              onTap: playing ? service.pause : service.play,
              child: Semantics(
                label: playing ? 'Pause' : 'Play',
                button: true,
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
              icon: _SkipIntervalIcon(
                seconds: SettingsStore.skipForwardSeconds,
                forward: true,
                size: 28,
                color: SagaColors.fgMuted,
              ),
              color: SagaColors.fgMuted,
              tooltip:
                  'Skip forward ${SettingsStore.skipForwardSeconds} seconds',
              // Same rule as the rewind button: one handler, shared with the
              // notification (seekAbsolute clamps to the book bounds itself).
              onPressed: service.fastForward,
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

  const _BottomActions({required this.service, required this.bookKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final speed =
        ref.watch(playbackSpeedProvider).valueOrNull ?? service.player.speed;
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
              onTap: () =>
                  showSpeedSheet(context, service: service, bookKey: bookKey),
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
              onTap: () => showCastSheet(context, service: service),
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
                  showSleepTimerSheet(context, ref, isActive,
                      service: service);
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

    // One creation path — NamedBookmark.create owns the id scheme and the
    // default label. This flow used to mint hex-microsecond ids of its own,
    // a second scheme alongside the store's UUIDs.
    final bm = NamedBookmark.create(
      bookRatingKey: key,
      trackRatingKey: track.ratingKey,
      positionMs: positionMs,
      trackTitle: track.title,
    );
    await showBookmarkEditSheet(
      context,
      title: 'Add bookmark',
      positionMs: positionMs,
      initialLabel: bm.label,
      onSave: (label, note) {
        ref
            .read(bookmarkNotifierProvider(key).notifier)
            .add(bm.copyWith(label: label, note: note));
        ref.read(bookmarkRevisionProvider.notifier).state++;
        if (context.mounted) {
          showSagaToast(context, 'Bookmark added: $label');
        }
      },
    );
  }
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
    // accentText, not accent: the 10px label below is body-sized text.
    final color = active ? SagaColors.accentText : SagaColors.fgMuted;
    // Gesture outside, Semantics inside — see the play/pause control above.
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Semantics(
        label: semanticLabel ?? label,
        button: true,
        excludeSemantics: true,
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
