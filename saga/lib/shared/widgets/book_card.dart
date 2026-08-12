import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/book_progress.dart';
import '../../core/plex/models/plex_book.dart';
import '../../core/providers.dart';
import '../../core/storage/bookmark_store.dart';
import '../../core/storage/completed_books_store.dart';
import '../../core/theme/saga_theme.dart';
import '../../features/library/book_detail_screen.dart';
import '../../features/player/player_provider.dart';
import 'book_cover_image.dart';

// ── Card geometry ─────────────────────────────────────────────────────────────
//
// The card lays out to a known height, so a grid's cell extent and a carousel's
// strip height are derived from it rather than guessed. They were guessed
// before: Home's strip was a hand-tuned 170 that the card had to shrink its type
// to fit inside, and Browse's grid a childAspectRatio that left ~34 dp for ~51 dp
// of text, so a wrapped title crowded the author line (issue #3).

/// Cover → title.
const double kBookCardTitleGap = 4;

/// Two lines of [bookCardTitleStyle], whether the title wraps or not — so the
/// author line sits at the same height on every card in a row.
///
/// A function of the text scale, not a constant: hardcoded 1.0× boxes clipped
/// wrapped titles into the author line at Android's large font settings.
///
/// The ceil is per line, not on the total — the text engine rounds each line's
/// height up to a whole pixel, so two 19.5 px lines lay out as 40, not 39.
double bookCardTitleHeight(TextScaler textScaler) =>
    (textScaler.scale(bookCardTitleStyle.fontSize!) *
                bookCardTitleStyle.height!)
            .ceilToDouble() *
        2;

/// Title → author.
const double kBookCardAuthorGap = 2;

/// One line of [bookCardAuthorStyle].
double bookCardAuthorHeight(TextScaler textScaler) =>
    (textScaler.scale(bookCardAuthorStyle.fontSize!) *
            bookCardAuthorStyle.height!)
        .ceilToDouble();

/// Rounding slack, so a cell is never a fraction of a pixel short.
const double _slack = 2;

/// Colour comes from the theme at build time; the metrics are what the layout
/// above is measured against (see `book_card_test.dart`).
const TextStyle bookCardTitleStyle = TextStyle(fontSize: 12, height: 1.25);
const TextStyle bookCardAuthorStyle = TextStyle(fontSize: 11, height: 1.3);

/// Cover width used by the horizontal book strips on Home.
const double kBookStripCoverWidth = 120;

/// Total height of a [BookCard] whose square cover is [coverWidth] wide.
///
/// Use for a grid's `mainAxisExtent` and for the height of a strip of cards.
/// [textScaler] is required, not defaulted: a call site that forgets it lays
/// out 1.0× boxes that clip at large font sizes — the bug this fixed.
double bookCardExtent(double coverWidth,
        {bool showAuthor = true, required TextScaler textScaler}) =>
    coverWidth +
    kBookCardTitleGap +
    bookCardTitleHeight(textScaler) +
    (showAuthor ? kBookCardAuthorGap + bookCardAuthorHeight(textScaler) : 0) +
    _slack;

/// Height of a horizontal strip of [BookCard]s at the standard cover width.
double bookStripHeight(TextScaler textScaler) =>
    bookCardExtent(kBookStripCoverWidth, textScaler: textScaler);

/// Grid delegate for a page of [BookCard]s.
///
/// Sizes each cell from the width the grid actually hands it, so it can't be
/// told a different padding than the one the caller used — the reason the
/// numbers are here at all. Pass [showAuthor] to the cards as well: it is the
/// one thing the cell height depends on that the delegate can't see.
SliverGridDelegate bookGridDelegate(
        {bool showAuthor = true, required TextScaler textScaler}) =>
    _BookGridDelegate(showAuthor: showAuthor, textScaler: textScaler);

class _BookGridDelegate extends SliverGridDelegate {
  static const _crossAxisCount = 3;
  static const _spacing = 10.0;

  final bool showAuthor;
  final TextScaler textScaler;

  const _BookGridDelegate({required this.showAuthor, required this.textScaler});

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    // crossAxisExtent already has the grid's padding taken out of it.
    final coverW =
        (constraints.crossAxisExtent - _spacing * (_crossAxisCount - 1)) /
            _crossAxisCount;
    final extent =
        bookCardExtent(coverW, showAuthor: showAuthor, textScaler: textScaler);
    return SliverGridRegularTileLayout(
      crossAxisCount: _crossAxisCount,
      mainAxisStride: extent + _spacing,
      crossAxisStride: coverW + _spacing,
      childMainAxisExtent: extent,
      childCrossAxisExtent: coverW,
      reverseCrossAxis: axisDirectionIsReversed(constraints.crossAxisDirection),
    );
  }

  @override
  bool shouldRelayout(_BookGridDelegate old) =>
      old.showAuthor != showAuthor || old.textScaler != textScaler;
}

// ── The card ──────────────────────────────────────────────────────────────────

/// The one book card: square cover, progress, downloaded mark, title, author.
///
/// Home's strips, Browse's grid and an author's books all draw this. They drew
/// three near-copies before, which had already drifted apart in title weight,
/// author size and spacing, and disagreed about whether to show progress at all.
class BookCard extends ConsumerWidget {
  final PlexBook book;

  /// Fixed cover width for a horizontal strip. Null fills the grid cell.
  final double? width;

  /// Off on a page that already names the author — an author's own books.
  final bool showAuthor;

  final bool selectMode;
  final bool selected;

  /// Defaults to opening the book's detail screen.
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const BookCard({
    super.key,
    required this.book,
    this.width,
    this.showAuthor = true,
    this.selectMode = false,
    this.selected = false,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watched for reactivity; the badge itself is store-derived so it can be
    // honest about completeness (all tracks, not just the first).
    ref.watch(downloadNotifierProvider);
    final hasDownload = isBookFullyDownloaded(book.ratingKey);
    final textScaler = MediaQuery.textScalerOf(context);

    return GestureDetector(
      onTap: onTap ??
          () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => BookDetailScreen(book: book)),
              ),
      onLongPress: onLongPress,
      // One TalkBack stop per card (title + author merged), announced as a
      // button; in multi-select the tick state rides along as "selected".
      child: MergeSemantics(
        child: Semantics(
          button: true,
          selected: selectMode ? selected : null,
          child: SizedBox(
            width: width,
            child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1.0,
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: BookCoverImage(thumbPath: book.thumbPath),
                  ),
                  BookProgressOverlay(book: book),
                  if (!selectMode && hasDownload)
                    Positioned(
                      bottom: 6,
                      right: 6,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: SagaColors.bg.withValues(alpha: 0.85),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.download_done_rounded,
                            color: SagaColors.accent, size: 12),
                      ),
                    ),
                  if (selectMode)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: selected
                              ? SagaColors.accent.withValues(alpha: 0.3)
                              : SagaColors.accentFg.withValues(alpha: 0.3),
                        ),
                        child: selected
                            ? Icon(Icons.check_circle_rounded,
                                color: SagaColors.accent, size: 28)
                            : Icon(Icons.radio_button_unchecked,
                                color: SagaColors.fgMuted, size: 28),
                      ),
                    ),
                ],
              ),
            ),
                const SizedBox(height: kBookCardTitleGap),
                SizedBox(
                  height: bookCardTitleHeight(textScaler),
                  child: Text(book.title,
                      style: bookCardTitleStyle.copyWith(color: SagaColors.fg),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ),
                if (showAuthor && book.authorName != null) ...[
                  const SizedBox(height: kBookCardAuthorGap),
                  Text(book.authorName!,
                      style: bookCardAuthorStyle.copyWith(
                          color: SagaColors.fgSubtle),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Progress bar (or completed tick) drawn over a square cover.
///
/// Lives here rather than beside one screen because every grid of books shows
/// it — a grid that says less about a book than the grid next door reads as a
/// bug, not as a different view.
class BookProgressOverlay extends ConsumerWidget {
  final PlexBook book;
  const BookProgressOverlay({super.key, required this.book});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(bookmarkRevisionProvider);
    ref.watch(completionRevisionProvider);

    if (CompletedBooksStore.isCompleted(book.ratingKey)) {
      return Positioned(
        top: 6,
        right: 6,
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: SagaColors.accent,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.check, color: SagaColors.accentFg, size: 13),
        ),
      );
    }

    final pos = BookmarkStore.load(book.ratingKey);
    if (pos == null || pos.absolutePositionMs <= 0) {
      return const SizedBox.shrink();
    }

    // A started book always shows something: a floor of 4% when the fraction is
    // known so the sliver is visible, and 8% when the length isn't known at all
    // — "started, can't say how far" rather than an empty bar.
    final fraction = bookProgressFraction(book, pos);
    final progress = fraction?.clamp(0.04, 1.0) ?? 0.08;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
        child: LinearProgressIndicator(
          value: progress,
          backgroundColor: Colors.black45,
          valueColor: AlwaysStoppedAnimation<Color>(SagaColors.accent),
          minHeight: 5,
        ),
      ),
    );
  }
}
