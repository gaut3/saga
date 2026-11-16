import '../plex_time.dart';

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
      // Null-guarded: Plex can return partially-indexed items with missing
      // fields, and one bad track must not crash the whole list parse.
      ratingKey: json['ratingKey']?.toString() ?? '',
      key: json['key'] as String? ?? '',
      title: json['title'] as String? ?? '',
      bookTitle: json['parentTitle'] as String?,
      authorName: json['grandparentTitle'] as String?,
      thumbPath: json['parentThumb'] as String?,
      // num, not int: some servers emit durations as floats, and PlexBook
      // already reads this same field the tolerant way.
      durationMs: (json['duration'] as num?)?.toInt() ?? 0,
      index: (json['index'] as num?)?.toInt() ?? 0,
      partKey: part?['key'] as String? ?? '',
      partFile: part?['file'] as String?,
      viewOffsetMs: plexViewOffsetMs(json['viewOffset']),
      lastViewedAt: plexLastViewedAt(json['lastViewedAt']),
    );
  }
}
