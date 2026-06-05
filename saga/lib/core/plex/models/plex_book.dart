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
  });

  factory PlexBook.fromJson(Map<String, dynamic> json) {
    final tags = (json['Collection'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map((c) => c['tag']?.toString() ?? '')
        .where((t) => t.isNotEmpty)
        .toList();
    return PlexBook(
      ratingKey: json['ratingKey'].toString(),
      title: json['title'] as String? ?? '',
      authorName: json['parentTitle'] as String?,
      thumbPath: json['thumb'] as String?,
      year: json['year'] as int?,
      leafCount: json['leafCount'] as int?,
      summary: json['summary'] as String?,
      totalDurationMs: json['duration'] as int?,
      studio: json['studio'] as String?,
      collectionTags: tags,
    );
  }
}
