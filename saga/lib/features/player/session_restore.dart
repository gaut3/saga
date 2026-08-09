import '../../core/storage/bookmark_store.dart';

/// The book with the most recently saved position — the same "latest thing you
/// listened to" that Continue Listening surfaces. Null when nothing is saved.
///
/// [completed] books are skipped, and for the same reason Continue Listening
/// skips them: finishing a book *saves a position at the very end*, so without
/// the filter the freshest bookmark is often the book just finished — and the
/// resumption card would offer to "resume" it seconds before the credits,
/// re-firing completion.
///
/// Pure function (extracted from the audio service's session restore) so the
/// selection logic is unit-testable without Hive.
String? mostRecentBookRatingKey(Map<String, BookPosition> positions,
    {Set<String> completed = const {}}) {
  String? bestKey;
  DateTime? bestAt;
  positions.forEach((key, pos) {
    if (completed.contains(key)) return;
    if (bestAt == null || pos.savedAt.isAfter(bestAt!)) {
      bestKey = key;
      bestAt = pos.savedAt;
    }
  });
  return bestKey;
}
