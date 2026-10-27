/// Whether a book is finished *now* — the one rule every "continue" surface,
/// the book screen's toggle and the finished badge share.
///
/// "Ever finished" is history and lives in [CompletedBooksStore]; it used to
/// double as "finished now", which locked every re-read out of Continue
/// Listening, the resume card, Android Auto and session restore (restore even
/// brought back an *older* book over it). The only way out was marking the book
/// not finished, which deleted its completion history. Now a completion stops
/// counting as "finished now" when the book is picked up again or reopened.
library;

import 'book_progress.dart';
import 'storage/bookmark_store.dart';
import 'storage/completed_books_store.dart';
import 'storage/listening_history_store.dart';
import 'storage/playback_log_store.dart';

/// Pure form of [isBookFinished], for tests.
///
/// Finished = completed, and since the last completion neither:
///  * marked not finished ([reopenedAt] at or after it), nor
///  * picked up again: *played* after it ([lastPlayAt], from the playback
///    log) while the saved place is a real mid-book position
///    ([isResumablePosition]) — not the end-of-book spot a finish leaves.
///
/// Played, not saved: the first version compared the saved position's time,
/// but the player also saves when the app goes to the background, paused or
/// not, so a book marked finished while loaded in the player came straight
/// back as "in progress".
///
/// A completion from before per-finish dates were kept (stored as epoch 0)
/// gets no re-read detection: there's no date to compare a play against, and
/// the original listen may still be in the log. It stays finished until
/// marked not finished — the old behaviour, for those books only.
bool isFinishedNow({
  required DateTime? lastCompletion,
  required DateTime? reopenedAt,
  required BookPosition? saved,
  required DateTime? lastPlayAt,
}) {
  if (lastCompletion == null) return false;
  // Not before, rather than after: a marker can only exist if it was written
  // after the last completion (finishing again deletes it), so a same-
  // millisecond tie is a reopen, not a finish.
  if (reopenedAt != null && !reopenedAt.isBefore(lastCompletion)) return false;
  final undated = lastCompletion.millisecondsSinceEpoch == 0;
  if (!undated &&
      lastPlayAt != null &&
      lastPlayAt.isAfter(lastCompletion) &&
      isResumablePosition(saved)) {
    return false;
  }
  return true;
}

/// Whether [ratingKey] is finished now. See [isFinishedNow].
bool isBookFinished(String ratingKey) => isFinishedNow(
      lastCompletion: CompletedBooksStore.lastCompletion(ratingKey),
      reopenedAt: CompletedBooksStore.reopenedAt(ratingKey),
      saved: BookmarkStore.load(ratingKey),
      lastPlayAt: PlaybackLogStore.lastPlayAt(ratingKey),
    );

/// Every book finished now — the set "continue" surfaces exclude.
Set<String> finishedBookKeys() => {
      for (final key in CompletedBooksStore.allCompleted())
        if (isBookFinished(key)) key,
    };

/// Records a finish: the completion (history + finished state) *and* the day's
/// entry in the listening record. The one path for both ways a book gets
/// finished — playing to the end and marking it by hand. The hand-marked path
/// used to write only the first, so the Month tab counted the book and the
/// Day tab never showed it.
Future<void> recordBookFinished({
  required String ratingKey,
  String? title,
  String? thumbPath,
}) async {
  await CompletedBooksStore.markCompleted(ratingKey);
  ListeningHistoryStore.recordCompleted(
      ratingKey: ratingKey, title: title, thumbPath: thumbPath);
}
