/// One entry from a Plex tag listing — `/library/sections/{key}/genre`,
/// `/style`, `/mood` and friends all return the same `Directory` shape.
///
/// Audiobook libraries keep the narrator in **Style**, so a narrator is a
/// [PlexTag] too.
class PlexTag {
  final String id;
  final String title;

  const PlexTag({required this.id, required this.title});

  factory PlexTag.fromJson(Map<String, dynamic> json) {
    // key looks like "/library/sections/1/style/123" — last segment is the ID
    final key = json['key'] as String? ?? '';
    final id = key.split('/').where((s) => s.isNotEmpty).last;
    return PlexTag(
      id: id,
      title: json['title'] as String? ?? '',
    );
  }
}
