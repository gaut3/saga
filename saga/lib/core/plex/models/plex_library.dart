class PlexLibrary {
  final String key;
  final String title;
  final String type;

  const PlexLibrary({
    required this.key,
    required this.title,
    required this.type,
  });

  factory PlexLibrary.fromJson(Map<String, dynamic> json) {
    // Tolerant like PlexTrack.fromJson: Plex servers vary by version, and a
    // hard cast here turned one odd section into "no libraries at all".
    return PlexLibrary(
      key: json['key'].toString(),
      title: json['title'] as String? ?? '',
      type: json['type'] as String? ?? '',
    );
  }

  bool get isMusic => type == 'artist';
}
