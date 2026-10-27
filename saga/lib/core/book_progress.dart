/// How long a book is, and how far through it the listener is — derived in one
/// place so every surface showing either agrees.
///
/// Both take the saved position rather than reading it, so the derivation stays
/// pure and callers that already hold one don't pay for a second lookup. Pass
/// `BookmarkStore.load(book.ratingKey)`, or null when the book has never been
/// started.
library;

import 'plex/models/plex_book.dart';
import 'storage/bookmark_store.dart';

/// The book's total length in ms, or null when neither source knows it.
///
/// Plex's own duration is authoritative, but the album API omits it for some
/// libraries and returns zero for others. The saved position carries the sum of
/// the track durations, recorded the first time the book played, and covers
/// that case.
///
/// Seven call sites used to spell this out with three different rules: some
/// without the `> 0` guard, so a Plex zero won and the progress bar vanished;
/// the book's own screen and the player's flipped cover without the fallback at
/// all, so they showed nothing for a book Home was happily drawing a bar for.
int? bookTotalDurationMs(PlexBook book, BookPosition? saved) =>
    pickTotalDurationMs(book.totalDurationMs, saved?.totalDurationMs);

/// [bookTotalDurationMs] for the surfaces that hold the two numbers but not a
/// [PlexBook] — History's session panel, which may not have found the book.
int? pickTotalDurationMs(int? fromPlex, int? fromSaved) {
  if (fromPlex != null && fromPlex > 0) return fromPlex;
  if (fromSaved != null && fromSaved > 0) return fromSaved;
  return null;
}

/// How far through the book, 0.0–1.0. Null when the position or the length is
/// unknown — callers decide whether that means "hide" or "zero", which differs
/// by surface.
///
/// Always measured from the book-absolute position. The per-track position is
/// meaningless as book progress on a multi-file book, and the book screen used
/// to pass it: a twenty-file book sitting on file twelve reported 2%.
double? bookProgressFraction(PlexBook book, BookPosition? saved) {
  if (saved == null) return null;
  final total = bookTotalDurationMs(book, saved);
  if (total == null) return null;
  return (saved.absolutePositionMs / total).clamp(0.0, 1.0);
}

/// How close to the end a saved position must sit to count as the artifact a
/// finish leaves behind rather than a place worth resuming.
const _endOfBookMarginMs = 10000;

/// Whether [saved] is a real mid-book place — not absent, not the end-of-book
/// position a finish writes. The advance resumes only these: "resuming" an
/// end-of-book bookmark replays the final second, completes again, and — with
/// auto-play on — cascades an advance through every finished book after it.
/// One rule, shared by `playNextBook`, the finished panel's buttons and
/// [isFinishedNow] — what the panel offers, what the advance does and what
/// counts as a re-read can't disagree.
bool isResumablePosition(BookPosition? saved) {
  if (saved == null) return false;
  if (saved.absolutePositionMs <= 0) return false;
  final total = saved.totalDurationMs;
  // Unknown length: can't tell the end from the middle — resume, the choice
  // that never discards a real place.
  if (total == null || total <= 0) return true;
  return total - saved.absolutePositionMs > _endOfBookMarginMs;
}
