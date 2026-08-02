import 'models/plex_author.dart';
import 'models/plex_book.dart';
import 'models/plex_tag.dart';
import 'models/plex_library.dart';
import 'models/plex_track.dart';
import 'plex_client.dart';

class PlexApi {
  final PlexClient _client;

  PlexApi(this._client);

  Future<List<T>> _fetchList<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    String containerKey = 'Metadata',
    required T Function(Map<String, dynamic>) fromJson,
  }) async {
    final response = await _client.get<Map<String, dynamic>>(path,
        queryParameters: queryParameters);
    final items = response.data?['MediaContainer']?[containerKey]
            as List<dynamic>? ??
        [];
    return items.map((i) => fromJson(i as Map<String, dynamic>)).toList();
  }

  Future<List<PlexLibrary>> fetchLibraries() async {
    final items = await _fetchList(
      '/library/sections',
      containerKey: 'Directory',
      fromJson: PlexLibrary.fromJson,
    );
    return items.where((l) => l.isMusic).toList();
  }

  Future<List<PlexBook>> fetchBooks(String sectionKey) async {
    const pageSize = 300;
    var start = 0;
    final results = <PlexBook>[];
    while (true) {
      final response = await _client.get<Map<String, dynamic>>(
        '/library/sections/$sectionKey/all',
        queryParameters: {
          'type': 9,
          'X-Plex-Container-Start': start,
          'X-Plex-Container-Size': pageSize,
        },
      );
      final container =
          response.data?['MediaContainer'] as Map<String, dynamic>?;
      final page = (container?['Metadata'] as List<dynamic>? ?? [])
          .map((i) => PlexBook.fromJson(i as Map<String, dynamic>))
          .toList();
      results.addAll(page);
      final total = (container?['totalSize'] as num?)?.toInt() ??
          (container?['size'] as num?)?.toInt() ??
          page.length;
      if (results.length >= total || page.isEmpty) break;
      start += pageSize;
    }
    return results;
  }

  Future<List<PlexBook>> fetchRecentlyAdded(String sectionKey,
          {int limit = 20}) =>
      _fetchList('/library/sections/$sectionKey/recentlyAdded',
          queryParameters: {'type': 9, 'X-Plex-Container-Size': limit},
          fromJson: PlexBook.fromJson);

  Future<List<PlexAuthor>> fetchAuthors(String sectionKey) =>
      _fetchList('/library/sections/$sectionKey/all',
          queryParameters: {'type': 8}, fromJson: PlexAuthor.fromJson);

  Future<List<PlexBook>> fetchBooksByAuthor(String authorRatingKey) =>
      _fetchList('/library/metadata/$authorRatingKey/children',
          fromJson: PlexBook.fromJson);

  Future<List<PlexBook>> fetchBooksInCollection(
      String sectionKey, String collectionRatingKey) async {
    // Approach 1: direct children endpoint (used by plexapi and most Plex clients)
    final r1 = await _client.get<Map<String, dynamic>>(
      '/library/metadata/$collectionRatingKey/children',
    );
    final items1 = (r1.data?['MediaContainer']?['Metadata'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    if (items1.isNotEmpty) {
      return items1.map(PlexBook.fromJson).toList();
    }

    // Approach 2: section filter using collection.id (Plex filter API)
    final r2 = await _client.get<Map<String, dynamic>>(
      '/library/sections/$sectionKey/all',
      queryParameters: {'type': 9, 'collection.id': collectionRatingKey},
    );
    final items2 = (r2.data?['MediaContainer']?['Metadata'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    if (items2.isNotEmpty) {
      return items2.map(PlexBook.fromJson).toList();
    }

    // Approach 3: filter using collection tag ID
    final r3 = await _client.get<Map<String, dynamic>>(
      '/library/sections/$sectionKey/all',
      queryParameters: {'type': 9, 'collection.tag.id': collectionRatingKey},
    );
    final items3 = (r3.data?['MediaContainer']?['Metadata'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    return items3.map(PlexBook.fromJson).toList();
  }

  /// The full record for one book, as the raw Plex map.
  ///
  /// The list endpoints return an abbreviated item — `Style` (where audiobook
  /// libraries keep the narrator), `Genre` and friends only appear here. Raw
  /// rather than a [PlexBook] so the caller can cache exactly what the server
  /// said and re-parse it later against a newer model.
  ///
  /// Returns null when the server has no such item.
  Future<Map<String, dynamic>?> fetchBookMetadataRaw(String ratingKey) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/library/metadata/$ratingKey',
    );
    final items =
        response.data?['MediaContainer']?['Metadata'] as List<dynamic>?;
    if (items == null || items.isEmpty) return null;
    final first = items.first;
    return first is Map<String, dynamic>
        ? first
        : Map<String, dynamic>.from(first as Map);
  }

  Future<List<PlexBook>> fetchCollections(String sectionKey) =>
      _fetchList('/library/sections/$sectionKey/collections',
          fromJson: PlexBook.fromJson);

  Future<List<PlexTag>> fetchGenres(String sectionKey) async {
    final items = await _fetchList(
      '/library/sections/$sectionKey/genre',
      containerKey: 'Directory',
      fromJson: PlexTag.fromJson,
    );
    return items.where((g) => g.title.isNotEmpty).toList();
  }

  Future<List<PlexBook>> fetchBooksByGenre(
          String sectionKey, String genreId) =>
      _fetchList('/library/sections/$sectionKey/all',
          queryParameters: {'type': 9, 'genre': genreId},
          fromJson: PlexBook.fromJson);

  /// Every narrator in the section, in one request.
  ///
  /// Plex has no narrator concept — audiobook libraries put it in Style, and
  /// Plex indexes Style, which is what makes narrator searchable and sortable
  /// without fetching each book's record separately.
  Future<List<PlexTag>> fetchNarrators(String sectionKey) async {
    final items = await _fetchList(
      '/library/sections/$sectionKey/style',
      containerKey: 'Directory',
      fromJson: PlexTag.fromJson,
    );
    return items.where((s) => s.title.isNotEmpty).toList();
  }

  /// The books credited to one narrator (Style), server-side filtered.
  Future<List<PlexBook>> fetchBooksByNarrator(
          String sectionKey, String styleId) =>
      _fetchList('/library/sections/$sectionKey/all',
          queryParameters: {'type': 9, 'style': styleId},
          fromJson: PlexBook.fromJson);

  Future<List<PlexBook>> searchBooks(String sectionKey, String query) =>
      _fetchList('/library/sections/$sectionKey/search',
          queryParameters: {'type': 9, 'query': query},
          fromJson: PlexBook.fromJson);

  Future<List<PlexTrack>> fetchTracks(String bookRatingKey) async {
    final tracks = await _fetchList(
      '/library/metadata/$bookRatingKey/children',
      fromJson: PlexTrack.fromJson,
    );
    return tracks..sort((a, b) => a.index.compareTo(b.index));
  }

  Future<void> reportTimeline({
    required String ratingKey,
    required String key,
    required int positionMs,
    required int durationMs,
    required String state,
  }) async {
    await _client.post<void>(
      '/:/timeline',
      queryParameters: {
        'ratingKey': ratingKey,
        'key': key,
        'state': state,
        'time': positionMs,
        'duration': durationMs,
        'hasMDE': 1,
      },
    );
  }
}
