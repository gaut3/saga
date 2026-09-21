import 'dart:async';

import 'package:flutter/services.dart';

import '../diagnostics/app_log.dart';

enum CastState { idle, connecting, connected }

class CastDevice {
  final String id;
  final String name;

  const CastDevice({required this.id, required this.name});
}

/// What was handed to the Cast device, captured at load time — the position a
/// session reports back is meaningless without it. The service used to keep a
/// bare position int, and the session-end writeback seeked whatever book the
/// local player happened to hold *then*: cast book A, play book B on the phone,
/// switch the TV off hours later, and B was seeked to A's position and saved.
class CastHandoff {
  final String bookRatingKey;
  final String trackRatingKey;

  /// Absolute offset of the cast track's start within the book, so a
  /// track-relative cast position converts to a whole-book one.
  final int trackStartMs;
  final int? totalDurationMs;

  const CastHandoff({
    required this.bookRatingKey,
    required this.trackRatingKey,
    required this.trackStartMs,
    this.totalDurationMs,
  });

  /// Round-trips through [SettingsStore] so a relaunch mid-cast can keep
  /// tracking the session the Cast SDK auto-resumes. Rating keys are numeric,
  /// so '|' is a safe separator.
  String serialize() =>
      '$bookRatingKey|$trackRatingKey|$trackStartMs|${totalDurationMs ?? ''}';

  static CastHandoff? tryParse(String raw) {
    final parts = raw.split('|');
    if (parts.length != 4 || parts[0].isEmpty || parts[1].isEmpty) return null;
    final startMs = int.tryParse(parts[2]);
    if (startMs == null) return null;
    return CastHandoff(
      bookRatingKey: parts[0],
      trackRatingKey: parts[1],
      trackStartMs: startMs,
      totalDurationMs: int.tryParse(parts[3]),
    );
  }
}

class CastService {
  static const _channel = MethodChannel('com.gaut3.saga/cast');

  final _stateController = StreamController<CastState>.broadcast();
  final _devicesController = StreamController<List<CastDevice>>.broadcast();
  final _errorController = StreamController<String>.broadcast();
  CastState _state = CastState.idle;
  List<CastDevice> _devices = const [];

  /// Fires once per session, on the connected→idle transition — TV switched
  /// off, Wi-Fi drop, someone else casting over us, or a deliberate
  /// Disconnect — with the handoff identity and the freshest position the
  /// device reported (0 when it never answered). This is where the local
  /// bookmark gets the cast position back; it used to live only under the
  /// sheet's Disconnect button, and the sheet is usually long closed when a
  /// session actually ends, so hours of listening were lost.
  Future<void> Function(CastHandoff handoff, int positionMs)? onSessionEnded;

  /// Fires on every position poll tick, so the position is durable *during*
  /// the session — a bare in-memory field meant an app killed mid-cast lost
  /// everything back to the moment casting started.
  Future<void> Function(CastHandoff handoff, int positionMs)? onPositionUpdate;

  // Freshest position seen this session, polled every 10 s (the same cadence
  // as local saves) — the fallback when the device vanishes without
  // answering a final query.
  Timer? _positionPoll;
  int? _lastKnownPositionMs;
  CastHandoff? _handoff;

  CastService() {
    _channel.setMethodCallHandler(_onNativeCall);
  }

  /// Identity of what's being cast; set at load time, cleared when the
  /// session ends.
  CastHandoff? get handoff => _handoff;

  void beginSession(CastHandoff h) {
    _handoff = h;
  }

  /// Asks native whether a Cast session is already live — the SDK auto-resumes
  /// one across a process restart, and its callbacks may fire before the Dart
  /// handler exists. Moves to `connected` (starting the position poll) when it
  /// is. Returns whether a session was found.
  Future<bool> syncSessionState() async {
    try {
      final connected =
          await _channel.invokeMethod<bool>('getSessionState') ?? false;
      if (connected && _state != CastState.connected) {
        _setState(CastState.connected);
      }
      return connected;
    } on PlatformException {
      return false;
    }
  }

  CastState get state => _state;
  Stream<CastState> get stateStream => _stateController.stream;
  List<CastDevice> get devices => _devices;
  Stream<List<CastDevice>> get devicesStream => _devicesController.stream;

  /// Human-readable Cast failures (session start/resume errors, abnormal
  /// session ends) for the UI to surface — e.g. "TIMEOUT (15)".
  Stream<String> get errorStream => _errorController.stream;

  Future<dynamic> _onNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onSessionStateChanged':
        final connected = call.arguments['connected'] as bool? ?? false;
        final ended = call.arguments['ended'] as bool? ?? false;
        final errorMessage = call.arguments['errorMessage'] as String?;
        if (errorMessage != null) {
          final code = call.arguments['errorCode'];
          final reason = '$errorMessage ($code)';
          if (ended) {
            // Session end always carries a reason code, even for a deliberate
            // Disconnect — log it (useful for unexpected drops) but don't
            // surface it as an error.
            AppLog.log('cast', 'session ended: $reason');
          } else {
            AppLog.log('cast', 'session failed: $reason');
            if (!_errorController.isClosed) _errorController.add(reason);
          }
        }
        _setState(connected ? CastState.connected : CastState.idle);
      case 'onRoutesChanged':
        final raw = call.arguments as List<dynamic>? ?? const [];
        _devices = raw
            .map((r) => CastDevice(
                  id: r['id']?.toString() ?? '',
                  name: r['name']?.toString() ?? 'Cast device',
                ))
            .where((d) => d.id.isNotEmpty)
            .toList();
        // isClosed guard: a native callback can land after dispose, and an
        // add on a closed controller throws inside the method-call handler.
        if (!_devicesController.isClosed) _devicesController.add(_devices);
    }
  }

  void _setState(CastState s) {
    final was = _state;
    _state = s;
    if (!_stateController.isClosed) _stateController.add(s);
    if (s == CastState.connected) {
      _startPositionPoll();
    } else if (was == CastState.connected && s == CastState.idle) {
      _stopPositionPoll();
      final pos = _lastKnownPositionMs;
      final h = _handoff;
      _lastKnownPositionMs = null;
      _handoff = null;
      // Fires even with no position (pos 0): the handler also owns clearing
      // the persisted handoff, which must happen however the session ends.
      if (h != null) unawaited(onSessionEnded?.call(h, pos ?? 0));
    }
  }

  void _startPositionPoll() {
    _positionPoll?.cancel();
    _positionPoll = Timer.periodic(const Duration(seconds: 10), (_) async {
      final pos = await getCastPosition();
      if (pos != null && pos > 0) {
        _lastKnownPositionMs = pos;
        final h = _handoff;
        if (h != null) unawaited(onPositionUpdate?.call(h, pos));
      }
    });
  }

  void _stopPositionPoll() {
    _positionPoll?.cancel();
    _positionPoll = null;
  }

  /// Starts active Cast device discovery; device list updates arrive on
  /// [devicesStream]. Call [stopDiscovery] when the picker UI closes —
  /// active scanning costs battery.
  Future<void> startDiscovery() async {
    try {
      await _channel.invokeMethod('startDiscovery');
    } on PlatformException {
      // Cast framework unavailable (no Play services) — list stays empty.
    }
  }

  Future<void> stopDiscovery() async {
    try {
      await _channel.invokeMethod('stopDiscovery');
    } on PlatformException {
      // ignore
    }
  }

  /// Connects to the device; [stateStream] emits `connected` when the Cast
  /// session is up (or back to `idle` if the session fails to start).
  Future<void> selectDevice(CastDevice device) async {
    try {
      _setState(CastState.connecting);
      // Deliberately not the device's name: a Cast device is usually named
      // after its owner or their living room, and this log is meant to be safe
      // to paste into a public issue. Same rule the audio-routing entries
      // follow, which record the kind of output and never what it is called.
      AppLog.log('cast', 'connecting to a cast device');
      await _channel.invokeMethod('selectRoute', {'id': device.id});
    } on PlatformException catch (e) {
      AppLog.log('cast', 'selectRoute failed: ${e.code} ${e.message}');
      _errorController.add(e.message ?? e.code);
      _setState(CastState.idle);
    }
  }

  /// Loads a track onto the active Cast session. [url] must be fetchable by
  /// the Cast device itself — never a `file://` path — and comes from
  /// `PlexClient.buildCastMedia`, which decides which credential it carries.
  /// Note that a Cast receiver's status, this URL included, is readable over
  /// the network by anything that asks, so nothing else belongs in it.
  Future<void> loadMedia({
    required String url,
    required String title,
    required String artist,
    String artwork = '',
    String contentType = 'audio/mpeg',
    int positionMs = 0,
  }) async {
    try {
      AppLog.log('cast', 'loadMedia $contentType pos=${positionMs}ms url=$url');
      await _channel.invokeMethod('loadMedia', {
        'url': url,
        'title': title,
        'artist': artist,
        'artwork': artwork,
        'contentType': contentType,
        'positionMs': positionMs,
      });
    } on PlatformException catch (e) {
      // Session may have dropped; reset state
      AppLog.log('cast', 'loadMedia failed: ${e.code} ${e.message}');
      _setState(CastState.idle);
    }
  }

  /// Current playback position on the Cast device in milliseconds. Null when
  /// the device can't answer (session gone) — distinct from a genuine 0, so
  /// an unreachable device falls back to the last polled value instead of
  /// silently discarding the position.
  Future<int?> getCastPosition() async {
    try {
      final pos = await _channel.invokeMethod<int>('getCastPosition');
      return (pos != null && pos > 0) ? pos : null;
    } on PlatformException {
      return null;
    }
  }

  Future<void> stopCasting() async {
    // A deliberate disconnect can still ask the device — take one fresh
    // reading before tearing the session down, so the session-end handler
    // gets the exact position rather than one up to 10 s stale.
    final pos = await getCastPosition();
    if (pos != null && pos > 0) _lastKnownPositionMs = pos;
    try {
      await _channel.invokeMethod('stopCasting');
    } on PlatformException {
      // ignore
    }
    _setState(CastState.idle);
  }

  void dispose() {
    _stopPositionPoll();
    _stateController.close();
    _devicesController.close();
    _errorController.close();
  }
}

/// MIME type for the Cast receiver, derived from the track's file name.
/// The Default Media Receiver uses this to pick a decoder — `audio/mpeg`
/// for an M4B makes playback unreliable.
String castContentTypeFor(String? fileName) {
  final ext = (fileName?.split('.').last ?? '').toLowerCase();
  switch (ext) {
    case 'm4b':
    case 'm4a':
    case 'mp4':
      return 'audio/mp4';
    case 'ogg':
    case 'opus':
      return 'audio/ogg';
    case 'flac':
      return 'audio/flac';
    case 'wav':
      return 'audio/wav';
    case 'aac':
      return 'audio/aac';
    default:
      return 'audio/mpeg';
  }
}

