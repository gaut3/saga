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
    // key looks like "/library/sections/1/style/123" — last segment is the ID.
    // One Directory without a key (exactly the case the `?? ''` above was
    // written for) used to throw on `.last` of an empty iterable here, and
    // that one entry killed the whole tag listing — narrator index included.
    final key = json['key']?.toString() ?? '';
    final segments = key.split('/').where((s) => s.isNotEmpty);
    return PlexTag(
      id: segments.isEmpty ? '' : segments.last,
      title: json['title'] as String? ?? '',
    );
  }
}
