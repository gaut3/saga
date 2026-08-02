class PlexBook {
  final String ratingKey;
  final String title;
  final String? authorName;
  final String? thumbPath;
  final int? year;
  final int? leafCount;
  final String? summary;
  final int? totalDurationMs;
  final String? studio;
  final List<String> collectionTags;
  final int? seriesIndex;
  final String? sortTitle;

  /// Who reads the book.
  ///
  /// Plex's music schema has no narrator field, so audiobook libraries put it
  /// in **Style** — the convention the Audnexus agent writes and what this
  /// library uses. Empty when the library isn't tagged that way, so everything
  /// that shows it must degrade to hiding it.
  final List<String> narrators;

  final List<String> genres;

  const PlexBook({
    required this.ratingKey,
    required this.title,
    this.authorName,
    this.thumbPath,
    this.year,
    this.leafCount,
    this.summary,
    this.totalDurationMs,
    this.studio,
    this.collectionTags = const [],
    this.seriesIndex,
    this.sortTitle,
    this.narrators = const [],
    this.genres = const [],
  });

  /// Plex returns Collection/Style/Genre alike: a list of `{tag: "..."}`.
  ///
  /// Matched as a bare [Map], not `Map<String, dynamic>`. The same record comes
  /// back out of the metadata cache after a restart, and Hive returns nested
  /// maps as `Map<dynamic, dynamic>` — a stricter test drops every tag silently
  /// and the narrator vanishes on the second launch, with nothing to say it had
  /// ever been there.
  static List<String> _tags(Map<String, dynamic> json, String key) =>
      (json[key] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((c) => c['tag']?.toString() ?? '')
          .where((t) => t.isNotEmpty)
          .toList();

  /// Display form: "A, B" — audiobooks occasionally credit a full cast.
  String? get narratorLabel =>
      narrators.isEmpty ? null : narrators.join(', ');

  factory PlexBook.fromJson(Map<String, dynamic> json) {
    return PlexBook(
      ratingKey: json['ratingKey'].toString(),
      title: json['title'] as String? ?? '',
      authorName: json['parentTitle'] as String?,
      thumbPath: json['thumb'] as String?,
      year: json['year'] as int?,
      leafCount: json['leafCount'] as int?,
      summary: json['summary'] as String?,
      totalDurationMs: (json['duration'] as num?)?.toInt(),
      studio: json['studio'] as String?,
      collectionTags: _tags(json, 'Collection'),
      seriesIndex: json['parentIndex'] as int?,
      sortTitle: json['titleSort'] as String?,
      narrators: _tags(json, 'Style'),
      genres: _tags(json, 'Genre'),
    );
  }
}
