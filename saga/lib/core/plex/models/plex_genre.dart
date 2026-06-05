class PlexGenre {
  final String id;
  final String title;

  const PlexGenre({required this.id, required this.title});

  factory PlexGenre.fromJson(Map<String, dynamic> json) {
    // key looks like "/library/sections/1/genre/123" — last segment is the ID
    final key = json['key'] as String? ?? '';
    final id = key.split('/').where((s) => s.isNotEmpty).last;
    return PlexGenre(
      id: id,
      title: json['title'] as String? ?? '',
    );
  }
}
