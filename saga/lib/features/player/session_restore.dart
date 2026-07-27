import '../../core/storage/bookmark_store.dart';

/// The book with the most recently saved position — the same "latest thing you
/// listened to" that Continue Listening surfaces. Null when nothing is saved.
///
/// Pure function (extracted from the audio service's session restore) so the
/// selection logic is unit-testable without Hive.
String? mostRecentBookRatingKey(Map<String, BookPosition> positions) {
  String? bestKey;
  DateTime? bestAt;
  positions.forEach((key, pos) {
    if (bestAt == null || pos.savedAt.isAfter(bestAt!)) {
      bestKey = key;
      bestAt = pos.savedAt;
    }
  });
  return bestKey;
}
