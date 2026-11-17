import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../diagnostics/app_log.dart';
import '../storage/artwork_cache.dart';
import '../storage/book_metadata_store.dart';
import '../storage/download_store.dart';
import '../storage/server_scope.dart';
import 'models/plex_track.dart';

const _clientIdKey = 'plex_client_id';
const _tokenKey = 'plex_token';
const _serverUriKey = 'plex_server_uri';
const _machineIdKey = 'plex_machine_id';
const _serverTokenKey = 'plex_server_token';

class PlexClient {
  static PlexClient? _instance;
  static PlexClient get instance => _instance!;

  final Dio _dio;
  final FlutterSecureStorage _storage;
  String? _token;
  String? _serverToken;
  String? _clientId;
  String? _serverUri;
  String? _machineIdentifier;

  /// Developer options: make every Plex API call fail as if the server were
  /// unreachable. In memory only, so it ends with the process; a forgotten
  /// switch can't leave a beta looking broken.
  static bool simulateOffline = false;

  void Function()? onUnauthorized;
  bool _handlingUnauthorized = false;

  /// The media server answered 401. Not a sign-out: see [_onError]. Set to
  /// re-read the server list from plex.tv, which renews the server's token
  /// and, if the account token itself is dead, gets plex.tv's own 401.
  void Function()? onServerUnauthorized;
  DateTime? _lastServerUnauthorized;

  PlexClient._({
    required Dio dio,
    required FlutterSecureStorage storage,
  })  : _dio = dio,
        _storage = storage;

  /// Test-only: a client with an injected [dio] and no platform channels.
  /// The storage is never touched by the methods under test.
  @visibleForTesting
  PlexClient.forTest(
      {required Dio dio, String? serverUri, String? token, String? serverToken})
      : _dio = dio,
        _storage = const FlutterSecureStorage(),
        _serverUri = serverUri,
        _token = token,
        _serverToken = serverToken {
    _dio.interceptors.add(
        InterceptorsWrapper(onRequest: _onRequest, onError: _onError));
  }

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
        _clientIdKey, _tokenKey, _serverUriKey, _machineIdKey, _serverTokenKey,
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
    String? serverToken;
    try { serverToken = await storage.read(key: _serverTokenKey); } catch (_) {}

    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Accept': 'application/json',
        'X-Plex-Product': 'Saga',
        'X-Plex-Version': '1.0.0',
        'X-Plex-Platform': 'Android',
        'X-Plex-Client-Identifier': clientId,
        // No token here: which one a request carries depends on where it is
        // going, and [_onRequest] decides that per request.
      },
    ));

    final client = PlexClient._(dio: dio, storage: storage);
    client._token = token;
    client._serverToken = serverToken;
    client._clientId = clientId;
    client._serverUri = serverUri;
    client._machineIdentifier = machineId;
    _instance = client;

    dio.interceptors.add(InterceptorsWrapper(
        onRequest: client._onRequest, onError: client._onError));

    return client;
  }

  /// Whether [host] is plex.tv. Dot-boundary match: a media server named
  /// e.g. `not-plex.tv` (server URIs can be owner-controlled custom domains)
  /// must not pass for it.
  static bool _isPlexTv(String host) =>
      host == 'plex.tv' || host.endsWith('.plex.tv');

  /// Whether [uri] is on the selected media server: same scheme, host and
  /// port as the saved address.
  bool _isServer(Uri uri) {
    final saved = _serverUri == null ? null : Uri.tryParse(_serverUri!);
    return saved != null &&
        uri.scheme == saved.scheme &&
        uri.host == saved.host &&
        uri.port == saved.port;
  }

  /// Puts the right credential on a request, by where it is going.
  ///
  /// The account token opens the whole Plex account: every server, the
  /// account's details. It goes to plex.tv and nowhere else. A media server
  /// gets the token plex.tv issued for that one server ([serverToken]), which
  /// is what Plex's own apps send. This matters most for a server someone
  /// else shared with you: sent the account token, its owner (or anything
  /// logging on it) held a key to your account and your own servers.
  ///
  /// Any other host gets no credential at all.
  void _onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // Developer options' "Simulate offline": every Plex API call fails as an
    // unreachable server would, for the session. Not the audio (the player
    // fetches it itself) and not the connection re-check (its own client).
    if (simulateOffline) {
      handler.reject(DioException.connectionError(
        requestOptions: options,
        reason: 'simulated offline (developer options)',
      ));
      return;
    }
    final uri = options.uri;
    final String? credential;
    if (_isPlexTv(uri.host)) {
      // The network config refuses cleartext to plex.tv; this refuses to
      // build the request at all.
      credential = uri.scheme == 'https' ? _token : null;
    } else if (_isServer(uri)) {
      credential = serverToken;
    } else {
      credential = null;
    }
    if (credential != null) {
      options.headers['X-Plex-Token'] = credential;
    } else {
      options.headers.remove('X-Plex-Token');
    }
    handler.next(options);
  }

  /// Decides what a refusal means.
  ///
  /// Only plex.tv can say the account token is dead, so only its 401 or 403
  /// signs the listener out. A media server's 403 is about one item
  /// (restricted libraries, managed users). Its 401 used to sign out as well,
  /// and that deleted a good token whenever something else answered at the
  /// server's address: another Plex server on the same LAN address in someone
  /// else's house, a server that had lost its own sign-in, anything on an
  /// unencrypted network. Now it asks plex.tv ([onServerUnauthorized]), at
  /// most once a minute; plex.tv either renews the server's token or refuses
  /// the account token itself, which is the sign-out above.
  void _onError(DioException err, ErrorInterceptorHandler handler) {
    final status = err.response?.statusCode;
    final uri = err.requestOptions.uri;
    if (_isPlexTv(uri.host)) {
      if ((status == 401 || status == 403) && !_handlingUnauthorized) {
        // Explains any surprise sign-out: plex.tv rejected the token.
        AppLog.log('auth', '$status from plex.tv — clearing token');
        _handlingUnauthorized = true;
        _token = null;
        _serverToken = null;
        _storage.delete(key: _tokenKey); // fire-and-forget
        _storage.delete(key: _serverTokenKey);
        onUnauthorized?.call();
      }
    } else if (status == 401 && _token != null) {
      final now = DateTime.now();
      final last = _lastServerUnauthorized;
      if (last == null || now.difference(last) > const Duration(minutes: 1)) {
        _lastServerUnauthorized = now;
        AppLog.log('auth', '401 from the media server — asking plex.tv');
        onServerUnauthorized?.call();
      }
    }
    handler.next(err);
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
  String? get serverUri => _serverUri;
  String? get machineIdentifier => _machineIdentifier;
  bool get isAuthenticated => _token != null;

  Future<void> saveToken(String token) async {
    _handlingUnauthorized = false; // new token — reset intercept guard
    _token = token;
    await _storage.write(key: _tokenKey, value: token);
  }

  /// The credential for the selected media server: the token plex.tv issued
  /// for it, or the account token while none is stored (an install from
  /// before per-server tokens, until its first re-read of the server list).
  String? get serverToken => _serverToken ?? _token;

  /// Whether the server's own token is stored. False on an install that
  /// hasn't re-read the server list since per-server tokens arrived.
  bool get hasServerToken => _serverToken != null;

  /// Which key the server is being sent, as facts that are safe on a screen:
  /// for developer options. Neither key, and no address, is in it. Null with
  /// no server selected or signed out.
  ({bool serverKeyStored, bool sameAsAccountKey, bool encrypted, bool plexDirect})?
      get connectionFacts {
    final uri = _serverUri == null ? null : Uri.tryParse(_serverUri!);
    if (uri == null || _token == null) return null;
    return (
      serverKeyStored: _serverToken != null,
      sameAsAccountKey: _serverToken == null || _serverToken == _token,
      encrypted: uri.scheme == 'https',
      plexDirect: uri.host.endsWith('.plex.direct'),
    );
  }

  /// Stores the token plex.tv issued for the selected server, or clears it
  /// when the list carried none.
  Future<void> saveServerToken(String? token) async {
    _serverToken = token;
    if (token == null) {
      await _storage.delete(key: _serverTokenKey);
    } else {
      await _storage.write(key: _serverTokenKey, value: token);
    }
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

  /// Signs out. Throws only while the token is still stored, which is the one
  /// case where the caller must keep showing the account as signed in.
  /// Everything after the token is gone is best-effort and logged: with the
  /// credential off the device the user *is* signed out, and a leftover cache
  /// must not leave the screen saying otherwise.
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
    // First, and the only step allowed to throw. In-memory state is cleared
    // after it, so a failed delete leaves a session that still works rather
    // than one that looks signed in with no token behind it.
    await _storage.delete(key: _tokenKey);
    _token = null;
    _serverToken = null;
    _serverUri = null;
    _machineIdentifier = null;

    Future<void> bestEffort(String step, Future<void> Function() run) async {
      try {
        await run();
      } catch (e) {
        AppLog.log('auth', 'sign-out: $step failed: $e');
      }
    }

    await bestEffort('clearing server address', () async {
      await _storage.delete(key: _serverUriKey);
      await _storage.delete(key: _machineIdKey);
      await _storage.delete(key: _serverTokenKey);
    });
    // Re-point storage now rather than on next launch, so a signed-out session
    // reads the same (last-active server's) records it will read after a
    // restart. Callers stop playback first — see the sign-out flow in Settings.
    await bestEffort('storage scope', () => ServerScope.configure(null));

    // Signing out has to mean signing out. Credentials alone were being
    // cleared while every cover of the account's library stayed on disk — in
    // the image cache, keyed by a URL that used to carry the token itself.
    // Listening progress is deliberately kept: signing back in must not cost
    // anyone their place.
    await purgeCachedArtwork();

    // Same reasoning, different cache: the metadata box holds a title-and-
    // author record for every book ever opened. Books with a position or a
    // download keep theirs — those are what sign-out promises to keep, and
    // their records are what names them on the offline shelves.
    await bestEffort('metadata prune', () async {
      final pruned = await BookMetadataStore.pruneOrphans();
      if (pruned > 0) {
        AppLog.log('storage', 'sign-out pruned $pruned cached book records');
      }
    });
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

  /// The header for a request to the media server made outside this client's
  /// own Dio: audio, covers, downloads, the chapter reader. Never the account
  /// token when the server has its own (see [_onRequest]).
  Map<String, String> get authHeaders => {
    if (serverToken != null) 'X-Plex-Token': serverToken!,
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
  /// Nothing that leaves the app may use this either: for a [MediaItem] use
  /// `ArtworkCache.getLocalUri`, for the browse tree
  /// `ArtworkCache.getSharedUri`, and for a Cast device [buildCastMedia].
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
  ///
  /// Null when the server didn't answer at all. That is not "wouldn't mint
  /// one": the Cast device would be handed URLs at an address this phone just
  /// failed to reach, and would sit loading forever (#24) — with the account
  /// token in them, spent for nothing.
  Future<({String token, bool isDelegated})?> _urlSafeToken() async {
    // The fallback when the server won't mint a delegated token: the server's
    // own token where there is one, so even the weaker case exposes one
    // server, not the account.
    final fallback = serverToken;
    if (fallback == null || _serverUri == null) return null;
    try {
      // Same endpoint Plex's own clients use to hand a stream to something that
      // can't authenticate. `scope=all` is Plex's only supported scope here.
      final response = await _dio
          .get<Map<String, dynamic>>(
            '$_serverUri/security/token',
            queryParameters: {'type': 'delegation', 'scope': 'all'},
            options: Options(
              sendTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 5),
            ),
          )
          // The client's connect timeout is 10 s; the listener is waiting on
          // this with the book paused.
          .timeout(const Duration(seconds: 5));
      // XML `<MediaContainer token="…">` becomes a nested key in JSON; older
      // servers have been seen putting it at the top level.
      final data = response.data;
      final delegated = (data?['MediaContainer']?['token'] ?? data?['token'])
          as String?;
      if (delegated != null && delegated.isNotEmpty) {
        return (token: delegated, isDelegated: true);
      }
      AppLog.log('cast', 'delegation endpoint returned no token');
    } on DioException catch (e) {
      if (e.response == null) {
        AppLog.log('cast', 'server unreachable for a cast token (${e.type.name})');
        return null;
      }
      AppLog.log('cast', 'delegated token unavailable: $e');
    } on TimeoutException {
      AppLog.log('cast', 'server unreachable for a cast token (timeout)');
      return null;
    } catch (e) {
      AppLog.log('cast', 'delegated token unavailable: $e');
    }
    return (token: fallback, isDelegated: false);
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
  ///  * Without one, the URLs carry the account token — a key to the whole
  ///    Plex account. That is the price of casting at all: every file of the
  ///    queue needs it, and they're readable from the same receiver, so more
  ///    files expose nothing more. [artUrl] is null, because exposing it to
  ///    one more consumer buys only a thumbnail.
  ///
  /// Always a server URL, never a local file — the Cast device can't reach the
  /// phone's storage. One URL per part, in order: a book is cast as a queue of
  /// its files, all carrying the one token minted here.
  Future<({List<String> streamUrls, String? artUrl})?> buildCastMedia({
    required List<String> partKeys,
    String? thumbPath,
  }) async {
    final serverUri = _serverUri;
    if (serverUri == null) return null;
    final credential = await _urlSafeToken();
    if (credential == null) return null;

    final token = Uri.encodeQueryComponent(credential.token);
    return (
      streamUrls: [
        for (final partKey in partKeys)
          '$serverUri$partKey?X-Plex-Token=$token',
      ],
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
