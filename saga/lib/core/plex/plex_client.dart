import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../diagnostics/app_log.dart';
import '../storage/artwork_cache.dart';
import '../storage/download_store.dart';
import '../storage/server_scope.dart';
import 'models/plex_track.dart';

const _clientIdKey = 'plex_client_id';
const _tokenKey = 'plex_token';
const _serverUriKey = 'plex_server_uri';
const _machineIdKey = 'plex_machine_id';

class PlexClient {
  static PlexClient? _instance;
  static PlexClient get instance => _instance!;

  final Dio _dio;
  final FlutterSecureStorage _storage;
  String? _token;
  String? _clientId;
  String? _serverUri;
  String? _machineIdentifier;

  void Function()? onUnauthorized;
  bool _handlingUnauthorized = false;

  PlexClient._({
    required Dio dio,
    required FlutterSecureStorage storage,
  })  : _dio = dio,
        _storage = storage;

  static Future<PlexClient> init() async {
    const storage = FlutterSecureStorage();
    String clientId;
    String? token;
    String? serverUri;

    // Read each key independently so a single corrupted entry does not wipe
    // unrelated credentials (e.g. a bad serverUri read must not clear the token).
    try {
      clientId = await _ensureClientId(storage);
    } catch (_) {
      // Recover by discarding only the Plex entries — never deleteAll(): the
      // Hive encryption key lives in this same secure-storage namespace, and
      // wiping it would make every encrypted box — positions, history,
      // settings — unreadable on the next launch.
      for (final key in const [
        _clientIdKey, _tokenKey, _serverUriKey, _machineIdKey,
      ]) {
        try { await storage.delete(key: key); } catch (_) {}
      }
      clientId = const Uuid().v4();
      try { await storage.write(key: _clientIdKey, value: clientId); } catch (_) {}
    }
    try { token = await storage.read(key: _tokenKey); } catch (_) {}
    try { serverUri = await storage.read(key: _serverUriKey); } catch (_) {}
    String? machineId;
    try { machineId = await storage.read(key: _machineIdKey); } catch (_) {}

    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Accept': 'application/json',
        'X-Plex-Product': 'Saga',
        'X-Plex-Version': '1.0.0',
        'X-Plex-Platform': 'Android',
        'X-Plex-Client-Identifier': clientId,
        if (token != null) 'X-Plex-Token': token,
      },
    ));

    final client = PlexClient._(dio: dio, storage: storage);
    client._token = token;
    client._clientId = clientId;
    client._serverUri = serverUri;
    client._machineIdentifier = machineId;
    _instance = client;

    dio.interceptors.add(InterceptorsWrapper(
      onError: (err, handler) {
        final status = err.response?.statusCode;
        // 401 always means the token is no longer good. 403 does not: a media
        // server returns it for content this account may not see (restricted
        // libraries, managed users), and treating that as a bad token signed
        // the listener out over a single unplayable item. Only plex.tv's 403
        // is about the credential itself.
        // Dot-boundary match: a media server named e.g. `not-plex.tv` (server
        // URIs can be owner-controlled custom domains) must not pass for
        // plex.tv, or its ordinary per-item 403s would sign the user out.
        final host = err.requestOptions.uri.host;
        final isPlexTv = host == 'plex.tv' || host.endsWith('.plex.tv');
        final tokenRejected = status == 401 || (status == 403 && isPlexTv);
        if (tokenRejected && !client._handlingUnauthorized) {
          // Explains any surprise sign-out: the server rejected the token.
          AppLog.log('auth',
              '$status from ${err.requestOptions.uri} — clearing token');
          client._handlingUnauthorized = true;
          client._token = null;
          dio.options.headers.remove('X-Plex-Token');
          storage.delete(key: _tokenKey); // fire-and-forget
          client.onUnauthorized?.call();
        }
        handler.next(err);
      },
    ));

    return client;
  }

  static Future<String> _ensureClientId(FlutterSecureStorage storage) async {
    var id = await storage.read(key: _clientIdKey);
    if (id == null) {
      id = const Uuid().v4();
      await storage.write(key: _clientIdKey, value: id);
    }
    return id;
  }

  String get clientId => _clientId!;
  String? get token => _token;
  String? get serverUri => _serverUri;
  String? get machineIdentifier => _machineIdentifier;
  bool get isAuthenticated => _token != null;
  bool get hasServer => _serverUri != null;

  Future<void> saveToken(String token) async {
    _handlingUnauthorized = false; // new token — reset intercept guard
    _token = token;
    _dio.options.headers['X-Plex-Token'] = token;
    await _storage.write(key: _tokenKey, value: token);
  }

  Future<void> saveServerUri(String uri) async {
    _serverUri = uri;
    await _storage.write(key: _serverUriKey, value: uri);
  }

  Future<void> saveMachineIdentifier(String id) async {
    _machineIdentifier = id;
    await _storage.write(key: _machineIdKey, value: id);
  }

  Future<void> clearServerUri() async {
    _serverUri = null;
    await _storage.delete(key: _serverUriKey);
  }

  Future<void> clearAuth() async {
    if (_token != null) {
      try {
        await _dio.delete<void>(
          'https://plex.tv/users/sign_out.json',
          options: Options(
            sendTimeout: const Duration(seconds: 5),
            receiveTimeout: const Duration(seconds: 5),
          ),
        );
      } catch (_) {
        // Best-effort — continue with local cleanup regardless
      }
    }
    _token = null;
    _serverUri = null;
    _machineIdentifier = null;
    _dio.options.headers.remove('X-Plex-Token');
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _serverUriKey);
    await _storage.delete(key: _machineIdKey);
    // Re-point storage now rather than on next launch, so a signed-out session
    // reads the same (last-active server's) records it will read after a
    // restart. Callers stop playback first — see the sign-out flow in Settings.
    await ServerScope.configure(null);

    // Signing out has to mean signing out. Credentials alone were being
    // cleared while every cover of the account's library stayed on disk — in
    // the image cache, keyed by a URL that used to carry the token itself.
    // Listening progress is deliberately kept: signing back in must not cost
    // anyone their place.
    await purgeCachedArtwork();
  }

  /// Drops every locally cached cover: the image cache and the artwork cache.
  ///
  /// Both are derived data that re-fetches on demand, so this is only ever a
  /// cost in bandwidth. Called on sign-out, and once on upgrade to clear
  /// entries written when the cache key still had a token in it.
  ///
  /// Returns false when either purge failed, so the one-time upgrade purge
  /// records *success*, not an attempt — a flag set on a failed purge would
  /// leave token-keyed rows on disk with nothing ever coming back for them.
  static Future<bool> purgeCachedArtwork() async {
    var ok = true;
    try {
      await DefaultCacheManager().emptyCache();
    } catch (e) {
      ok = false;
      AppLog.log('storage', 'image cache purge failed: $e');
    }
    try {
      await ArtworkCache.clear();
    } catch (e) {
      ok = false;
      AppLog.log('storage', 'artwork cache purge failed: $e');
    }
    return ok;
  }

  Map<String, String> get authHeaders => {
    if (_token != null) 'X-Plex-Token': _token!,
  };

  Future<Response<T>> get<T>(
    String path, {
    String? baseUrl,
    Map<String, dynamic>? queryParameters,
  }) async {
    final base = baseUrl ?? _serverUri;
    if (base == null) throw StateError('No Plex server configured');
    return _dio.get<T>('$base$path', queryParameters: queryParameters);
  }

  Future<Response<T>> post<T>(
    String path, {
    String? baseUrl,
    Map<String, dynamic>? queryParameters,
    dynamic data,
  }) async {
    final base = baseUrl ?? _serverUri;
    if (base == null) throw StateError('No Plex server configured');
    return _dio.post<T>('$base$path', queryParameters: queryParameters, data: data);
  }

  String? buildStreamUrl(String partKey) {
    if (_serverUri == null) return null;
    return '$_serverUri$partKey';
  }

  // For downloading a part to disk. `download=1` makes the server treat the
  // request as a file download instead of a playback stream — without it,
  // Plex tracks each GET as a streaming session and terminates the previous
  // one when the same client starts the next, so on multi-file books every
  // file except the last aborts mid-transfer.
  String? buildDownloadUrl(String partKey) {
    final url = buildStreamUrl(partKey);
    if (url == null) return null;
    return url.contains('?') ? '$url&download=1' : '$url?download=1';
  }

  /// An artwork URL with **no credential in it**, for in-app rendering.
  ///
  /// Pair it with [authHeaders]: every image widget in the app authenticates by
  /// header. That isn't only about what crosses the wire — `CachedNetworkImage`
  /// keys its on-disk cache by URL, so a token in the query string was being
  /// written to an unencrypted database and left there, still valid, long after
  /// the user signed out. A URL that never holds a token can't be cached into
  /// one.
  ///
  /// Nothing that leaves the app may use this either: for a [MediaItem] or the
  /// browse tree use `ArtworkCache.getLocalUri`, and for a Cast device use
  /// [buildCastMedia].
  String? buildThumbUrl(String? thumbPath) {
    if (thumbPath == null || _serverUri == null) return null;
    return '$_serverUri$thumbPath';
  }

  /// A token that may be put in a URL, and how much it is worth if read.
  ///
  /// Plex mints a *delegated* token on request: scoped to this one server and
  /// short-lived, where [token] is account-wide and permanent. Casting is the
  /// only path that has to put a credential in a URL, so it is the only path
  /// that asks for one.
  ///
  /// [isDelegated] is false when the server wouldn't mint one and the caller is
  /// holding the account token instead. Callers must treat that as the weaker
  /// case and put it in as few places as possible — see [buildCastMedia].
  Future<({String token, bool isDelegated})?> _urlSafeToken() async {
    final accountToken = _token;
    if (accountToken == null || _serverUri == null) return null;
    try {
      // Same endpoint Plex's own clients use to hand a stream to something that
      // can't authenticate. `scope=all` is Plex's only supported scope here.
      final response = await _dio.get<Map<String, dynamic>>(
        '$_serverUri/security/token',
        queryParameters: {'type': 'delegation', 'scope': 'all'},
        options: Options(
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );
      // XML `<MediaContainer token="…">` becomes a nested key in JSON; older
      // servers have been seen putting it at the top level.
      final data = response.data;
      final delegated = (data?['MediaContainer']?['token'] ?? data?['token'])
          as String?;
      if (delegated != null && delegated.isNotEmpty) {
        return (token: delegated, isDelegated: true);
      }
      AppLog.log('cast', 'delegation endpoint returned no token');
    } catch (e) {
      AppLog.log('cast', 'delegated token unavailable: $e');
    }
    return (token: accountToken, isDelegated: false);
  }

  /// The URLs a Cast device needs, and nothing more than it needs.
  ///
  /// A Chromecast fetches the stream itself and cannot send headers, so a token
  /// has to travel in the URL for this one path — and a casting receiver's
  /// status, `contentId` included, is readable over the Cast protocol by
  /// **anything else on the same network, unauthenticated**. So what goes in
  /// that URL is chosen here, once, rather than at the call site:
  ///
  ///  * With a delegated token, a listener on the network gets a short-lived
  ///    key to one server. Artwork comes along, since it costs nothing extra.
  ///  * Without one, the URL carries the account token — a key to the whole
  ///    Plex account. That is the price of casting at all, but it is paid once:
  ///    [artUrl] is null, because a second copy of it buys only a thumbnail.
  ///
  /// Always a server URL, never a local file — the Cast device can't reach the
  /// phone's storage.
  Future<({String streamUrl, String? artUrl})?> buildCastMedia({
    required String partKey,
    String? thumbPath,
  }) async {
    final serverUri = _serverUri;
    if (serverUri == null) return null;
    final credential = await _urlSafeToken();
    if (credential == null) return null;

    final token = Uri.encodeQueryComponent(credential.token);
    return (
      streamUrl: '$serverUri$partKey?X-Plex-Token=$token',
      artUrl: (credential.isDelegated && thumbPath != null)
          ? '$serverUri$thumbPath?X-Plex-Token=$token'
          : null,
    );
  }

  /// The downloaded file for [track], or null to stream it.
  ///
  /// Recorded *and* present: a record whose file is gone must fall through to
  /// the server rather than hand back a path that won't open. The audio service
  /// makes the same call when it builds its sources, so "do we have this
  /// locally" is decided once for chapter reading and playback alike.
  static String? localTrackPath(PlexTrack track) {
    final path = DownloadStore.getPath(track.ratingKey);
    if (path == null || !File(path).existsSync()) return null;
    return path;
  }

  String? resolveTrackUrl(PlexTrack track) {
    final localPath = localTrackPath(track);
    if (localPath != null) return 'file://$localPath';
    return buildStreamUrl(track.partKey);
  }

  String? resolveM4bParam(PlexTrack track) {
    final url = resolveTrackUrl(track);
    return url != null ? '${track.ratingKey}|$url' : null;
  }
}
