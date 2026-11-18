import '../plex_time.dart';
import '../rating_key.dart';

class PlexTrack {
  final String ratingKey;
  final String key;
  final String title;
  final String? bookTitle;
  final String? authorName;
  final String? thumbPath;
  final int durationMs;
  final int index;
  final String partKey;
  final String? partFile;

  /// Plex's progress for this file, as of the fetch: the offset in ms and
  /// when the server last heard a report for it (sync design rule 2). Null
  /// when Plex has none. Read from the server only, never cached: a copy
  /// from yesterday would say the wrong thing about who is newer.
  final int? viewOffsetMs;
  final DateTime? lastViewedAt;

  /// How many times Plex counts this file as played; null when it sent
  /// none. Shown in developer options only, to find out whether a file
  /// played to 90% loses its offset (sync design, open questions). No rule
  /// reads it yet.
  final int? viewCount;

  const PlexTrack({
    required this.ratingKey,
    required this.key,
    required this.title,
    required this.durationMs,
    required this.index,
    required this.partKey,
    this.bookTitle,
    this.authorName,
    this.thumbPath,
    this.partFile,
    this.viewOffsetMs,
    this.lastViewedAt,
    this.viewCount,
  });

  /// Flat map for local storage (offline track cache) — deliberately our own
  /// shape, not a reconstruction of the nested Plex JSON, so [fromJson] parsing
  /// quirks can't leak into the cache round-trip.
  Map<String, dynamic> toMap() => {
        'ratingKey': ratingKey,
        'key': key,
        'title': title,
        if (bookTitle != null) 'bookTitle': bookTitle,
        if (authorName != null) 'authorName': authorName,
        if (thumbPath != null) 'thumbPath': thumbPath,
        'durationMs': durationMs,
        'index': index,
        'partKey': partKey,
        if (partFile != null) 'partFile': partFile,
      };

  factory PlexTrack.fromMap(Map<dynamic, dynamic> map) => PlexTrack(
        ratingKey: map['ratingKey'] as String? ?? '',
        key: map['key'] as String? ?? '',
        title: map['title'] as String? ?? '',
        bookTitle: map['bookTitle'] as String?,
        authorName: map['authorName'] as String?,
        thumbPath: map['thumbPath'] as String?,
        durationMs: map['durationMs'] as int? ?? 0,
        index: map['index'] as int? ?? 0,
        partKey: map['partKey'] as String? ?? '',
        partFile: map['partFile'] as String?,
      );

  factory PlexTrack.fromJson(Map<String, dynamic> json) {
    final media = (json['Media'] as List<dynamic>?)?.firstOrNull;
    final part = (media?['Part'] as List<dynamic>?)?.firstOrNull;

    return PlexTrack(
      // Throws on a key that isn't one (rating_key.dart). Every caller parses
      // per item, so one bad track is dropped, not the list. The other fields
      // are null-guarded: Plex can return partially-indexed items.
      ratingKey: requireRatingKey(json['ratingKey']),
      key: json['key'] as String? ?? '',
      title: json['title'] as String? ?? '',
      bookTitle: json['parentTitle'] as String?,
      authorName: json['grandparentTitle'] as String?,
      thumbPath: serverPathOrNull(json['parentThumb']),
      // num, not int: some servers emit durations as floats, and PlexBook
      // already reads this same field the tolerant way.
      durationMs: (json['duration'] as num?)?.toInt() ?? 0,
      index: (json['index'] as num?)?.toInt() ?? 0,
      partKey: serverPathOrNull(part?['key']) ?? '',
      partFile: part?['file'] as String?,
      viewOffsetMs: plexViewOffsetMs(json['viewOffset']),
      lastViewedAt: plexLastViewedAt(json['lastViewedAt']),
      viewCount: plexViewCount(json['viewCount']),
    );
  }
}
