/// What a Plex id and a Plex path must look like before Saga uses them.
///
/// A rating key is an integer on every real server, but it arrives as text
/// from a server Saga doesn't control (Plex lists servers other people share
/// with you), and from other apps through the media session. It then goes
/// into server URLs (`/library/metadata/$key/children`), storage keys
/// (`ServerScope`, where `|` separates the server from the key) and download
/// filenames. A key with a slash, a dot, a `?` or a `|` in it stops being a
/// key in each of those places, so it is refused where it enters: at the
/// model, and again in `PlexApi` for the ids that come from outside the app.
library;

final _ratingKeyShape = RegExp(r'^[A-Za-z0-9_-]+$');

/// Whether [value] is usable as a rating key. Deliberately looser than "an
/// integer", so a server with an unusual key keeps working; what it excludes
/// is the punctuation that makes a key into a path.
bool isRatingKey(String value) => _ratingKeyShape.hasMatch(value);

/// [value] as a rating key, or a [FormatException]. The model parsers call
/// this; `PlexApi`'s lists drop the one item and keep the rest.
String requireRatingKey(Object? value) {
  final key = value?.toString() ?? '';
  if (!isRatingKey(key)) {
    throw const FormatException('not a usable rating key');
  }
  return key;
}

/// [value] as a path on the server, or null when it isn't one.
///
/// Stream and cover URLs are built as `$serverUri$path`. A "path" that
/// doesn't start with a slash rewrites the host: `https://server:32400` +
/// `@elsewhere/x` is a request to `elsewhere`, carrying the token.
String? serverPathOrNull(Object? value) {
  if (value is! String || !value.startsWith('/') || value.startsWith('//')) {
    return null;
  }
  if (value.contains(RegExp(r'[\s\\]'))) return null;
  return value;
}
