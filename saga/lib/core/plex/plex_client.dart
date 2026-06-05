import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../storage/download_store.dart';
import 'models/plex_track.dart';

const _clientIdKey = 'plex_client_id';
const _tokenKey = 'plex_token';
const _serverUriKey = 'plex_server_uri';

class PlexClient {
  static PlexClient? _instance;
  static PlexClient get instance => _instance!;

  final Dio _dio;
  final FlutterSecureStorage _storage;
  String? _token;
  String? _clientId;
  String? _serverUri;

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
      await storage.deleteAll();
      clientId = const Uuid().v4();
      try { await storage.write(key: _clientIdKey, value: clientId); } catch (_) {}
    }
    try { token = await storage.read(key: _tokenKey); } catch (_) {}
    try { serverUri = await storage.read(key: _serverUriKey); } catch (_) {}

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
    _instance = client;

    dio.interceptors.add(InterceptorsWrapper(
      onError: (err, handler) {
        final status = err.response?.statusCode;
        if ((status == 401 || status == 403) && !client._handlingUnauthorized) {
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
    _dio.options.headers.remove('X-Plex-Token');
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _serverUriKey);
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

  String? buildThumbUrl(String? thumbPath) {
    if (thumbPath == null || _serverUri == null) return null;
    return '$_serverUri$thumbPath';
  }

  // Used only for MediaItem.artUri (Android notification artwork).
  // Android's MediaSession fetches this URI natively and cannot accept custom
  // headers, so the token must remain in the URL for this one case.
  Uri? buildArtUri(String? thumbPath) {
    if (thumbPath == null || _serverUri == null || _token == null) return null;
    return Uri.parse('$_serverUri$thumbPath?X-Plex-Token=$_token');
  }

  String? resolveTrackUrl(PlexTrack track) {
    final localPath = DownloadStore.getPath(track.ratingKey);
    if (localPath != null && File(localPath).existsSync()) {
      return 'file://$localPath';
    }
    return buildStreamUrl(track.partKey);
  }

  String? resolveM4bParam(PlexTrack track) {
    final url = resolveTrackUrl(track);
    return url != null ? '${track.ratingKey}|$url' : null;
  }
}
