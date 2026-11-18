/// Removing a book's download once it has been listened to the end
/// (GitHub #29), for people who would otherwise clear finished books out of
/// their storage by hand.
///
/// Not at the moment of finishing. The finished book is still loaded then:
/// Play replays it from the start, off the files on the phone, and most books
/// finish in a pocket where nobody can say "keep it". So a finish only
/// *notes* the book, and the download goes when the listener has moved on:
/// another book is loaded, the player is dismissed, or Saga starts again.
/// Picking the book up again before that keeps it.
///
/// Only a book played to its end is noted. Marking one finished by hand
/// doesn't touch its download.
library;

import '../../core/book_status.dart';
import '../../core/diagnostics/app_log.dart';
import '../../core/storage/book_download_store.dart';
import '../../core/storage/server_scope.dart';
import '../../core/storage/settings_store.dart';

/// What happens to a noted book's download at a sweep.
enum FinishedDownloadFate {
  /// Still the book in the player: leave it for the next sweep.
  wait,

  /// Picked up again, marked not finished, or already deleted: nothing to
  /// remove, and no longer noted.
  forget,

  /// Finished and left behind: delete the download.
  remove,
}

FinishedDownloadFate finishedDownloadFate({
  required bool isLoaded,
  required bool finishedNow,
  required bool hasDownload,
}) {
  if (isLoaded) return FinishedDownloadFate.wait;
  if (!finishedNow || !hasDownload) return FinishedDownloadFate.forget;
  return FinishedDownloadFate.remove;
}

/// Notes that [bookRatingKey] was played to the end. Does nothing with the
/// setting off or for a book that isn't downloaded.
Future<void> noteFinishedDownload(String bookRatingKey) async {
  if (!SettingsStore.removeFinishedDownloads) return;
  if (!BookDownloadStore.hasDownload(bookRatingKey)) return;
  final key = ServerScope.key(bookRatingKey);
  final pending = SettingsStore.finishedDownloadsPending;
  if (pending.contains(key)) return;
  await SettingsStore.setFinishedDownloadsPending([...pending, key]);
}

/// Removes the downloads of noted books the listener has moved on from, and
/// returns the books removed.
///
/// [loadedBook] is the book in the player, which is never touched. [delete]
/// is `DownloadNotifier.deleteBookByKeys`, the one path for deleting a
/// download. Turning the setting off forgets everything noted.
Future<List<String>> sweepFinishedDownloads({
  required String? loadedBook,
  required Future<void> Function(String book, Set<String> tracks) delete,
  bool Function(String book) isFinished = isBookFinished,
}) async {
  final pending = SettingsStore.finishedDownloadsPending;
  if (pending.isEmpty) return const [];
  if (!SettingsStore.removeFinishedDownloads) {
    await SettingsStore.setFinishedDownloadsPending(const []);
    return const [];
  }
  final keep = <String>[];
  final removed = <String>[];
  for (final key in pending) {
    // Another server's book: its downloads can't be reached from this
    // scope. It waits for that server to be selected again.
    final book = ServerScope.ratingKeyOf(key);
    if (book == null) {
      keep.add(key);
      continue;
    }
    final fate = finishedDownloadFate(
      isLoaded: book == loadedBook,
      finishedNow: isFinished(book),
      hasDownload: BookDownloadStore.hasDownload(book),
    );
    switch (fate) {
      case FinishedDownloadFate.wait:
        keep.add(key);
      case FinishedDownloadFate.forget:
        break;
      case FinishedDownloadFate.remove:
        try {
          await delete(book, BookDownloadStore.trackKeys(book));
          removed.add(book);
          AppLog.log('download', 'removed the download of finished book $book');
        } catch (e) {
          // Still noted, so the next sweep tries again.
          AppLog.log('download', 'removing finished book $book failed: $e');
          keep.add(key);
        }
    }
  }
  await SettingsStore.setFinishedDownloadsPending(keep);
  return removed;
}
