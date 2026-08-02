import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../diagnostics/app_log.dart';
import '../providers.dart';
import '../storage/narrator_index_store.dart';
import 'plex_api.dart';

/// Progress of building a section's narrator index.
class NarratorIndexState {
  /// Narrators resolved so far, and how many there are in total.
  final int done;
  final int total;
  final bool building;

  /// Book rating key → narrators. Empty until a build has completed (or been
  /// loaded from the cache).
  final Map<String, List<String>> index;

  /// Set when the last build failed, so the UI can say so instead of silently
  /// showing an empty sort.
  final String? error;

  const NarratorIndexState({
    this.done = 0,
    this.total = 0,
    this.building = false,
    this.index = const {},
    this.error,
  });

  bool get isReady => index.isNotEmpty;
  double get progress => total == 0 ? 0 : done / total;

  NarratorIndexState copyWith({
    int? done,
    int? total,
    bool? building,
    Map<String, List<String>>? index,
    String? error,
    bool clearError = false,
  }) =>
      NarratorIndexState(
        done: done ?? this.done,
        total: total ?? this.total,
        building: building ?? this.building,
        index: index ?? this.index,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Builds and holds the book → narrators lookup for one library section.
///
/// The library listing has no narrator (Plex keeps it in `Style`), so this asks
/// Plex the question it *can* answer cheaply — "which books does this narrator
/// read" — once per narrator, and inverts the answers. That is one request per
/// narrator rather than one per book, and it only ever runs when the user
/// actually sorts or searches by narrator.
class NarratorIndexNotifier extends StateNotifier<NarratorIndexState> {
  final PlexApi _api;
  final String _sectionKey;

  /// Requests in flight at once. Enough to keep a LAN server busy without
  /// behaving like a stress test on someone's Raspberry Pi.
  static const _concurrency = 5;

  NarratorIndexNotifier(this._api, this._sectionKey)
      : super(const NarratorIndexState()) {
    final cached = NarratorIndexStore.load(_sectionKey);
    if (cached != null) state = state.copyWith(index: cached);
  }

  /// Builds the index unless one is already loaded. [force] re-reads the
  /// library, for when it has changed since.
  Future<void> build({bool force = false}) async {
    if (state.building) return;
    if (state.isReady && !force) return;

    state = state.copyWith(
        building: true, done: 0, total: 0, clearError: true);
    try {
      final narrators = await _api.fetchNarrators(_sectionKey);
      if (!mounted) return;
      if (narrators.isEmpty) {
        // A library with no Style tags at all: record the attempt so the UI can
        // explain rather than offering to index again and again.
        state = state.copyWith(
            building: false,
            error: 'No narrators are tagged in this library.');
        return;
      }
      state = state.copyWith(total: narrators.length);

      final collected = <({String narrator, List<String> bookKeys})>[];
      for (var i = 0; i < narrators.length; i += _concurrency) {
        if (!mounted) return;
        final chunk = narrators.skip(i).take(_concurrency).toList();
        final results = await Future.wait(chunk.map((tag) async {
          try {
            final books = await _api.fetchBooksByNarrator(_sectionKey, tag.id);
            return (
              narrator: tag.title,
              bookKeys: books.map((b) => b.ratingKey).toList()
            );
          } catch (e) {
            // One bad tag shouldn't sink the whole index.
            AppLog.log('plex', 'narrator index: "${tag.title}" failed: $e');
            return (narrator: tag.title, bookKeys: <String>[]);
          }
        }));
        collected.addAll(results);
        if (!mounted) return;
        state = state.copyWith(done: (i + chunk.length).clamp(0, narrators.length));
      }

      final index = invertNarratorIndex(collected);
      await NarratorIndexStore.save(_sectionKey, index);
      if (!mounted) return;
      state = state.copyWith(
          building: false, index: index, done: narrators.length);
      AppLog.log('plex',
          'narrator index built: ${index.length} books, ${narrators.length} narrators');
    } catch (e) {
      AppLog.log('plex', 'narrator index failed: $e');
      if (!mounted) return;
      state = state.copyWith(
          building: false, error: 'Could not reach the server.');
    }
  }
}

final narratorIndexProvider = StateNotifierProvider.family<
    NarratorIndexNotifier, NarratorIndexState, String>((ref, sectionKey) {
  return NarratorIndexNotifier(ref.watch(plexApiProvider), sectionKey);
});
