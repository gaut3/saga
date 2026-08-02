import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/plex/models/plex_book.dart';
import '../../core/plex/plex_client.dart';
import '../../core/providers.dart';

/// How many chapters a book really has.
///
/// Plex's `leafCount` is 1 for a single-file M4B no matter how many chapters
/// are embedded in it, so the honest count needs the tracks and — for the
/// single-file case — the embedded `chpl` markers.
///
/// Returns null while still resolving, so callers can hide the chip rather than
/// flash a wrong number. One function, two callers (book detail and the
/// player's flipped cover), so the two can't drift apart.
///
/// Call from a `build` method: it watches providers.
int? effectiveChapterCount(WidgetRef ref, PlexBook book) {
  final tracks = ref.watch(tracksProvider(book.ratingKey)).valueOrNull;
  if (tracks == null) return book.leafCount;
  if (tracks.length != 1) return tracks.length;

  final m4bParam = PlexClient.instance.resolveM4bParam(tracks[0]);
  if (m4bParam == null) return 1;

  final m4bAsync = ref.watch(m4bChaptersProvider(m4bParam));
  final chapters = m4bAsync.valueOrNull;
  if (chapters != null && chapters.isNotEmpty) return chapters.length;
  if (!m4bAsync.isLoading) return 1;
  return null; // still resolving — keep the chip hidden
}
