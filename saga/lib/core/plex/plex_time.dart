/// Plex's progress fields, read one way everywhere (sync design rule 4).
///
/// `lastViewedAt` is Unix **seconds** on the server's clock; `viewOffset` is
/// **milliseconds**. Chronicle compared the first with its own milliseconds
/// and decided every time on a 1000× error. These are the only readers.
library;

/// `lastViewedAt` → a time, or null when it's absent or not a sane value
/// (non-numeric, not positive, not finite, or past the year 2500: a number
/// that large made the DateTime below throw, which dropped the whole track
/// from the book's file list).
DateTime? plexLastViewedAt(Object? seconds) {
  if (seconds is! num || !seconds.isFinite || seconds <= 0) return null;
  if (seconds > 16725225600) return null;
  return DateTime.fromMillisecondsSinceEpoch((seconds * 1000).round(),
      isUtc: true);
}

/// `viewOffset` → ms, or null when absent or negative. Missing means "no
/// information" (a report under a minute erases it), never position 0.
int? plexViewOffsetMs(Object? ms) {
  if (ms is! num || !ms.isFinite || ms < 0) return null;
  return ms.round();
}
