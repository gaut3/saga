import '../rating_key.dart';

class PlexAuthor {
  final String ratingKey;
  final String title;
  final String? thumbPath;
  final int bookCount;

  const PlexAuthor({
    required this.ratingKey,
    required this.title,
    this.thumbPath,
    this.bookCount = 0,
  });

  factory PlexAuthor.fromJson(Map<String, dynamic> json) {
    // Tolerant like PlexTrack.fromJson: one partially-indexed artist must not
    // empty the whole author list.
    return PlexAuthor(
      ratingKey: requireRatingKey(json['ratingKey']),
      title: json['title'] as String? ?? '',
      thumbPath: serverPathOrNull(json['thumb']),
      bookCount: (json['childCount'] as num?)?.toInt() ?? 0,
    );
  }
}
