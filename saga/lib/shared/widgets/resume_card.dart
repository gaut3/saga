import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/book_progress.dart';
import '../../core/diagnostics/app_log.dart';
import '../../core/plex/models/plex_book.dart';
import '../../core/plex/models/plex_track.dart';
import '../../core/providers.dart';
import '../../core/storage/bookmark_store.dart';
import '../../core/storage/chapter_store.dart';
import '../../core/theme/saga_theme.dart';
import '../../core/utils/format.dart';
import '../../features/player/book_launch.dart';
import '../../features/player/open_player.dart';
import '../../features/player/player_provider.dart';
import '../../features/player/player_screen.dart';
import '../../features/player/track_position_math.dart';
import 'book_cover_image.dart';
import 'saga_mark.dart' show AnimatedSagaMark, SagaMarkState;
import 'saga_toast.dart';

/// The resume card: cover, title, the chapter at the saved position, time
/// left and %, and an accent footer that plays or pauses. Home's Continue
/// Listening hero today; the home-screen widget draws the same card natively
/// from [resumeChapterLabel], so the two can't disagree about the chapter.
///
/// No border: the footer's mark already says whether this book is playing.
class ResumeCard extends ConsumerStatefulWidget {
  final PlexBook book;
  const ResumeCard({super.key, required this.book});

  @override
  ConsumerState<ResumeCard> createState() => _ResumeCardState();
}

class _ResumeCardState extends ConsumerState<ResumeCard> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    // Clear loading state the moment this book actually starts playing,
    // so we jump straight from loading animation to playing animation
    // without a flash of the paused/resume state.
    ref.listen(nowPlayingKeyProvider, (_, next) {
      if (next.valueOrNull == widget.book.ratingKey && _loading) {
        setState(() => _loading = false);
      }
    });

    final savedPos = BookmarkStore.load(widget.book.ratingKey);
    final (:remainingMs, fraction: pct) = resumeProgress(widget.book, savedPos);

    final nowPlayingKey = ref.watch(nowPlayingKeyProvider).valueOrNull;
    final isNowPlaying = nowPlayingKey == widget.book.ratingKey;

    // Tracks are fetched lazily for the hero book so we can label the current
    // chapter; the result is cached and reused when the player opens.
    final tracks = ref.watch(tracksProvider(widget.book.ratingKey)).valueOrNull;
    final chapterLabel = resumeChapterLabel(tracks, savedPos);

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: ColoredBox(
        color: SagaColors.surface,
        child: Column(
          children: [
            // ── Tap the body to open the player ──
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _openPlayerView,
              // One TalkBack stop for the whole body, announced as a button;
              // title, chapter and remaining-time texts merge into it.
              child: MergeSemantics(
                child: Semantics(
                  button: true,
                  child: SizedBox(
                    height: 152,
                    child: Row(
                      children: [
                        // Square footprint so square covers aren't cropped on
                        // the sides (BoxFit.cover in a portrait box clipped
                        // left/right).
                        SizedBox(
                          width: 152,
                          height: 152,
                          child: BookCoverImage(
                            thumbPath: widget.book.thumbPath,
                            cacheWidth: kCoverCacheWidthCard,
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.book.title,
                                  style: TextStyle(
                                    color: SagaColors.fg,
                                    fontSize: 16,
                                    height: 1.3,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (chapterLabel != null) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    chapterLabel,
                                    style: TextStyle(
                                      color: SagaColors.fgMuted,
                                      fontSize: 12.5,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                                const Spacer(),
                                Row(
                                  children: [
                                    if (remainingMs != null)
                                      Text(
                                        '${fmtListenedMs(remainingMs)} left',
                                        style: TextStyle(
                                          color: SagaColors.fg,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    const Spacer(),
                                    Text(
                                      '${(pct * 100).round()}%',
                                      style: TextStyle(
                                        color: SagaColors.fgSubtle,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(3),
                                  child: LinearProgressIndicator(
                                    value: pct,
                                    backgroundColor: SagaColors.surfaceAlt,
                                    valueColor: AlwaysStoppedAnimation(
                                      SagaColors.accent,
                                    ),
                                    minHeight: 6,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // ── Accent footer: the primary play/pause action ──
            // accentDim, not accent: this is the widest amber area in the app
            // (see SagaColors.accentDim). Identical outside Onyx.
            Material(
              color: SagaColors.accentDim,
              child: InkWell(
                onTap: _loading ? null : (isNowPlaying ? _pause : _resume),
                child: SizedBox(
                  height: 52,
                  // Label is centred and the mark is pinned to a fixed spot, so
                  // neither jumps as the label changes width.
                  child: Stack(
                    children: [
                      Center(
                        child: Text(
                          _loading
                              ? 'Loading…'
                              : isNowPlaying
                              ? 'Pause'
                              : 'Resume listening',
                          style: TextStyle(
                            color: SagaColors.accentFg,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Positioned(
                        left: 24,
                        top: 0,
                        bottom: 0,
                        // Our own mark, monochrome on the accent button: the
                        // play triangle morphs to/from the pause bars, and the
                        // bars shimmer (converging into the pause glyph) while
                        // loading — no 4-spine flash in between.
                        child: Center(
                          child: AnimatedSagaMark(
                            size: 24,
                            monoColor: SagaColors.accentFg,
                            playPauseControl: true,
                            loading: _loading,
                            state: (isNowPlaying || _loading)
                                ? SagaMarkState.playing
                                : SagaMarkState.paused,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Tapping the card body opens the player. When the card's book is already
  /// the loaded one (playing or paused) that's a plain push; otherwise the
  /// book is loaded without starting audio, through the shared helper — the
  /// silent inline version left a blank "Now Playing" with no title and no
  /// error when the load failed, while the footer button right below
  /// explained itself.
  Future<void> _openPlayerView() async {
    final service = ref.read(playerServiceProvider);
    if (service.currentBookRatingKey == widget.book.ratingKey) {
      Navigator.of(
        context,
        rootNavigator: true,
      ).push(MaterialPageRoute(builder: (_) => const PlayerScreen()));
      return;
    }
    await openPlayerAndStart(
      context: context,
      service: service,
      bookRatingKey: widget.book.ratingKey,
      loadTracks: () => ref.read(tracksProvider(widget.book.ratingKey).future),
      from: const BookStartPoint.resume(),
      playback: LaunchPlayback.none,
    );
  }

  Future<void> _resume() async {
    if (_loading) return;
    final service = ref.read(playerServiceProvider);
    // The loaded book just plays; no loading state for that.
    final loaded = service.currentBookRatingKey == widget.book.ratingKey;
    if (!loaded) setState(() => _loading = true);
    try {
      await service.resumeBook(
        widget.book.ratingKey,
        loadTracks: () => ref.read(tracksProvider(widget.book.ratingKey).future),
      );
    } catch (e) {
      // "Loading…" quietly reverting to "Resume listening" reads as a dead
      // button — say what happened instead.
      AppLog.log('playback', 'home resume failed: $e');
      if (mounted) {
        showSagaToast(
          context,
          'Couldn\'t load this book — is the server reachable?',
          isError: true,
        );
      }
    } finally {
      if (mounted && _loading) setState(() => _loading = false);
    }
  }

  Future<void> _pause() async {
    await ref.read(playerServiceProvider).pause();
  }
}

/// The card's two progress figures: time left (null when the book's length
/// is unknown) and the fraction listened. The home-screen widget shows the
/// same two, from here.
({int? remainingMs, double fraction}) resumeProgress(
  PlexBook book,
  BookPosition? pos,
) {
  final total = bookTotalDurationMs(book, pos);
  final absolute = pos?.absolutePositionMs ?? 0;
  return (
    remainingMs: total != null ? (total - absolute).clamp(0, total) : null,
    fraction: bookProgressFraction(book, pos) ?? 0.0,
  );
}

/// The chapter title at the saved position, or null if unknown. Single-file
/// M4B books use the cached embedded chapters; multi-track books use the
/// track at the saved position. Reads only local stores, so it answers on a
/// cold start — the home-screen widget's snapshot uses it too.
///
/// The title alone, like the player. This was "Ch. N · Title", and a book
/// whose titles carry their own numbers read "Ch. 72 · 70. Setting People
/// Straight": the 72nd entry, two after an intro, is the author's chapter 70
/// (GitHub #17). "Ch. N" is only the fallback for an untitled chapter.
String? resumeChapterLabel(List<PlexTrack>? tracks, BookPosition? pos) {
  if (tracks == null || tracks.isEmpty || pos == null) return null;
  if (tracks.length == 1) {
    final chaps = ChapterStore.load(pos.trackRatingKey);
    if (chaps == null || chaps.isEmpty) return null;
    // Through the shared [chapterIndexAt], like the player, the mini player,
    // the notification and both chapter lists — this card was the seventh
    // hand-rolled copy of the same loop.
    final ci = chapterIndexAt([
      for (final c in chaps) c.start.inMilliseconds,
    ], pos.positionMs);
    return _titleOrNumber(chaps[ci].title, ci);
  }
  final idx = tracks.indexWhere((t) => t.ratingKey == pos.trackRatingKey);
  if (idx < 0) return null;
  return _titleOrNumber(tracks[idx].title, idx);
}

String _titleOrNumber(String title, int index) =>
    title.trim().isEmpty ? 'Ch. ${index + 1}' : title.trim();
