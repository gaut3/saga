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

  /// Every track handed to the device, in queue order, each with its start
  /// offset in the book, so a queue item's position converts to a place in
  /// the book. Every file of the book: it is cast as one queue.
  final List<({String trackRatingKey, int startMs})> tracks;
  final int? totalDurationMs;

  /// Names the queue load this handoff describes; every receiver status
  /// carries the load it belongs to. Null for a handoff written before load
  /// ids (v1, v2): its statuses are taken as they come, as they always were.
  final String? loadId;

  const CastHandoff({
    required this.bookRatingKey,
    required this.tracks,
    this.totalDurationMs,
    this.loadId,
  });

  /// Where the device is, as a place in the book: queue item [itemIndex] at
  /// [itemPositionMs]. Null for an index the handoff doesn't know, such as a
  /// status from an older queue: skipping a save is recoverable, filing a
  /// position under the wrong track is not.
  ({String trackRatingKey, int positionMs, int absoluteMs})? positionAt(
      int itemIndex, int itemPositionMs) {
    if (itemIndex < 0 || itemIndex >= tracks.length) return null;
    final t = tracks[itemIndex];
    final pos = itemPositionMs < 0 ? 0 : itemPositionMs;
    return (
      trackRatingKey: t.trackRatingKey,
      positionMs: pos,
      absoluteMs: t.startMs + pos,
    );
  }

  /// How long queue item [i] is, from the starts and the total; null when
  /// the total isn't known for the last item.
  int? itemDurationMs(int i) {
    if (i < 0 || i >= tracks.length) return null;
    if (i + 1 < tracks.length) return tracks[i + 1].startMs - tracks[i].startMs;
    final total = totalDurationMs;
    return total == null ? null : total - tracks[i].startMs;
  }

  /// Round-trips through [SettingsStore] so a relaunch mid-cast can keep
  /// tracking the session the Cast SDK auto-resumes. Rating keys are numeric,
  /// so '|', ',' and ':' are safe separators.
  /// The load id is digits and a dash.
  String serialize() => 'v3|$bookRatingKey|${totalDurationMs ?? ''}|'
      '${loadId ?? ''}|'
      '${tracks.map((t) => '${t.trackRatingKey}:${t.startMs}').join(',')}';

  /// Reads v3; v2, written before load ids; and the v1 form
  /// (`book|track|startMs|total`) written before the queue, so a cast running
  /// across an upgrade keeps its writeback.
  static CastHandoff? tryParse(String raw) {
    var parts = raw.split('|');
    String? loadId;
    if (parts.length == 5 && parts[0] == 'v3') {
      loadId = parts[3].isEmpty ? null : parts[3];
      parts = ['v2', parts[1], parts[2], parts[4]];
    }
    if (parts.length == 4 && parts[0] == 'v2') {
      if (parts[1].isEmpty || parts[3].isEmpty) return null;
      final tracks = <({String trackRatingKey, int startMs})>[];
      for (final entry in parts[3].split(',')) {
        final kv = entry.split(':');
        if (kv.length != 2 || kv[0].isEmpty) return null;
        final start = int.tryParse(kv[1]);
        if (start == null || start < 0) return null;
        tracks.add((trackRatingKey: kv[0], startMs: start));
      }
      return CastHandoff(
        bookRatingKey: parts[1],
        tracks: tracks,
        totalDurationMs: int.tryParse(parts[2]),
        loadId: loadId,
      );
    }
    if (parts.length != 4 || parts[0].isEmpty || parts[1].isEmpty) return null;
    final startMs = int.tryParse(parts[2]);
    if (startMs == null) return null;
    return CastHandoff(
      bookRatingKey: parts[0],
      tracks: [(trackRatingKey: parts[1], startMs: startMs)],
      totalDurationMs: int.tryParse(parts[3]),
    );
  }
}

/// The receiver's player state, as `RemoteMediaClient` reports it.
enum CastPlayerState { idle, loading, buffering, playing, paused, unknown }

/// One status push from the receiver: what it's doing, which queue item, and
/// where in that item. Positions are the item's own (file-relative), never
/// the book's: [CastHandoff.positionAt] converts.
class CastStatus {
  final CastPlayerState state;

  /// `finished`, `cancelled`, `interrupted`, `error` or `none`; only
  /// meaningful while [state] is idle.
  final String idleReason;

  /// The playing item's queue index, or -1 when the receiver didn't say
  /// (between items, after the queue ends).
  final int item;

  /// The load this status belongs to ([CastHandoff.loadId]); empty when the
  /// receiver didn't say.
  final String loadId;
  final int positionMs;
  final double rate;

  /// The device's own volume, 0–1 (what the TV's volume buttons move).
  final double? deviceVolume;

  /// When this status arrived, for extrapolating the position between pushes.
  final DateTime receivedAt;

  const CastStatus({
    required this.state,
    this.idleReason = 'none',
    this.item = -1,
    this.loadId = '',
    this.positionMs = 0,
    this.rate = 1.0,
    this.deviceVolume,
    required this.receivedAt,
  });

  static CastStatus? fromMap(Object? raw, {DateTime? now}) {
    if (raw is! Map) return null;
    final state = CastPlayerState.values.asNameMap()[raw['state']] ??
        CastPlayerState.unknown;
    return CastStatus(
      state: state,
      idleReason: raw['idleReason'] as String? ?? 'none',
      item: (raw['item'] as num?)?.toInt() ?? -1,
      loadId: raw['load'] as String? ?? '',
      positionMs: (raw['positionMs'] as num?)?.toInt() ?? 0,
      rate: (raw['rate'] as num?)?.toDouble() ?? 1.0,
      deviceVolume: (raw['deviceVolume'] as num?)?.toDouble(),
      receivedAt: now ?? DateTime.now(),
    );
  }

  bool get playing =>
      state == CastPlayerState.playing || state == CastPlayerState.buffering;

  /// The receiver played the last of what it was given. Whether that was the
  /// book's last file is the handler's call: it knows the last item it saw.
  bool get finished =>
      state == CastPlayerState.idle && idleReason == 'finished';

  /// The position now, moved on by the time since the push while playing.
  int positionNowMs([DateTime? now]) {
    if (state != CastPlayerState.playing) return positionMs;
    final elapsed = (now ?? DateTime.now()).difference(receivedAt);
    return positionMs + (elapsed.inMilliseconds * rate).round();
  }
}

/// Decides which receiver statuses may move the saved place.
///
/// A receiver reports position 0 while it loads, buffers a fresh item, or
/// sits idle after an error, and the writeback used to trust whatever came
/// back. Saving one of those over a real position is losing someone's place,
/// so a status counts only when:
/// - the receiver has settled since the last load: reported playing or paused
///   at least once (loading and the first buffering report the item's start,
///   not where the load asked to begin);
/// - it is playing, paused or buffering (idle carries no position worth
///   having);
/// - it belongs to this handoff's load (a status from the previous book's
///   queue, still playing while the next one loads, must never be read as a
///   place in the new book);
/// - it names a queue item the handoff knows, at a position inside that
///   item.
///
/// Anything else keeps the last good place, which stays the one the handler
/// saves.
class CastPositionTracker {
  final CastHandoff handoff;
  bool _settled = false;
  ({int item, int positionMs})? _last;

  CastPositionTracker(this.handoff);

  /// The last trustworthy place, or null before the first.
  ({int item, int positionMs})? get last => _last;

  /// Takes [s] into account; returns the place it reports when it counts.
  ({int item, int positionMs})? accept(CastStatus s) {
    final load = handoff.loadId;
    if (load != null && s.loadId != load) return null;
    if (s.state == CastPlayerState.playing ||
        s.state == CastPlayerState.paused) {
      _settled = true;
    }
    if (!_settled) return null;
    if (s.state != CastPlayerState.playing &&
        s.state != CastPlayerState.paused &&
        s.state != CastPlayerState.buffering) {
      return null;
    }
    if (s.item < 0 || s.item >= handoff.tracks.length) return null;
    if (s.positionMs < 0) return null;
    final dur = handoff.itemDurationMs(s.item);
    // A little slack: the receiver's clock and Plex's duration disagree by
    // a frame or two at the end of a file.
    if (dur != null && s.positionMs > dur + 5000) return null;
    return _last = (item: s.item, positionMs: s.positionMs);
  }
}

class CastService {
  static const _channel = MethodChannel('com.gaut3.saga/cast');

  final _stateController = StreamController<CastState>.broadcast();
  final _devicesController = StreamController<List<CastDevice>>.broadcast();
  final _errorController = StreamController<String>.broadcast();
  final _statusController = StreamController<CastStatus>.broadcast();
  CastState _state = CastState.idle;
  List<CastDevice> _devices = const [];
  CastStatus? _status;
  String? _deviceName;
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

  void clearHandoff() {
    _handoff = null;
  }

  CastState get state => _state;
  Stream<CastState> get stateStream => _stateController.stream;

  /// Counts sessions: a new one each time a device connects. Work that
  /// outlasts its session (a slow server between connect and load) compares
  /// this to tell whether the session it started for is still the one up.
  int get session => _session;
  int _session = 0;
  List<CastDevice> get devices => _devices;
  Stream<List<CastDevice>> get devicesStream => _devicesController.stream;

  /// The latest receiver status, null before the first of a session.
  CastStatus? get status => _status;
  Stream<CastStatus> get statusStream => _statusController.stream;

  /// The connected device's name, for the device sheet and the Device
  /// button. Someone's room or their own name: never logged.
  String? get deviceName => _deviceName;

  /// Human-readable Cast failures (session start/resume errors, abnormal
  /// session ends) for the UI to surface — e.g. "TIMEOUT (15)".
  Stream<String> get errorStream => _errorController.stream;

  /// For failures found on the Dart side (no server, a refused load), so the
  /// device sheet says them the same way.
  void reportError(String message) {
    if (!_errorController.isClosed) _errorController.add(message);
  }

  /// Asks native whether a Cast session is already live — the SDK auto-resumes
  /// one across a process restart, and its callbacks may fire before the Dart
  /// handler exists. Returns whether a session was found.
  Future<bool> syncSessionState() async {
    try {
      final raw = await _channel.invokeMethod<Map>('getSessionState');
      final connected = raw?['connected'] as bool? ?? false;
      if (connected) {
        _deviceName = raw?['deviceName'] as String? ?? _deviceName;
        if (_state != CastState.connected) _setState(CastState.connected);
        final s = await fetchStatus();
        if (s != null) _onStatus(s);
      }
      return connected;
    } on PlatformException {
      return false;
    }
  }

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
            reportError(reason);
          }
        }
        if (connected) {
          _deviceName = call.arguments['deviceName'] as String? ?? _deviceName;
        }
        // Moving to another device: the old session's end lands while the
        // new one connects, and isn't the new one failing.
        if (!connected && ended && _state == CastState.connecting) return;
        _setState(connected ? CastState.connected : CastState.idle);
      case 'onMediaStatus':
        final s = CastStatus.fromMap(call.arguments);
        if (s != null) _onStatus(s);
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

  void _onStatus(CastStatus s) {
    _status = s;
    if (!_statusController.isClosed) _statusController.add(s);
  }

  void _setState(CastState s) {
    if (s == _state) return;
    _state = s;
    if (s == CastState.connected) _session++;
    if (s == CastState.idle) {
      _status = null;
      _deviceName = null;
    }
    if (!_stateController.isClosed) _stateController.add(s);
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
      reportError(e.message ?? e.code);
      _setState(CastState.idle);
    }
  }

  /// Loads the whole book onto the receiver as one queue, starting at item
  /// [startIndex], [positionMs] into it, tagged [loadId]. Each item's `url` must be fetchable
  /// by the Cast device itself — never a `file://` path — and comes from
  /// `PlexClient.buildCastQueue`, which decides which credential it carries.
  /// A receiver's status, these URLs included, is readable over the network
  /// by anything that asks, so nothing else belongs in them. Returns whether
  /// the receiver accepted the load.
  Future<bool> loadQueue({
    required List<CastQueueItem> items,
    required String title,
    required String artist,
    String artwork = '',
    required int startIndex,
    required int positionMs,
    required bool autoplay,
    required double rate,
    required String loadId,
  }) async {
    try {
      // Never the URLs: they carry a token.
      AppLog.log('cast',
          'load queue: ${items.length} item(s), start $startIndex at ${positionMs}ms');
      return await _channel.invokeMethod<bool>('loadQueue', {
            'items': [
              for (final i in items)
                {
                  'url': i.url,
                  'contentType': i.contentType,
                  'durationMs': i.durationMs,
                  'trackTitle': i.trackTitle,
                },
            ],
            'title': title,
            'artist': artist,
            'artwork': artwork,
            'startIndex': startIndex,
            'positionMs': positionMs,
            'autoplay': autoplay,
            'rate': rate,
            'loadId': loadId,
          }) ??
          false;
    } on PlatformException catch (e) {
      AppLog.log('cast', 'queue load failed: ${e.code} ${e.message}');
      return false;
    }
  }

  Future<bool> _command(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<bool>(method, args) ?? false;
    } on PlatformException catch (e) {
      AppLog.log('cast', '$method failed: ${e.code} ${e.message}');
      return false;
    }
  }

  Future<bool> play() => _command('play');
  Future<bool> pause() => _command('pause');

  /// Seeks within the current item.
  Future<bool> seek(int positionMs) =>
      _command('seek', {'positionMs': positionMs});

  /// Jumps to queue item [index] at [positionMs]. False when the receiver's
  /// queue doesn't know the item; the caller reloads the queue instead.
  Future<bool> jump(int index, int positionMs) =>
      _command('jump', {'index': index, 'positionMs': positionMs});

  Future<bool> setRate(double rate) => _command('setRate', {'rate': rate});

  /// The stream's own volume, 0–1: the sleep timer's fade. The device's
  /// volume stays where the listener set it.
  Future<bool> setStreamVolume(double volume) =>
      _command('setStreamVolume', {'volume': volume});

  /// The device's volume, 0–1: the device sheet's slider and the phone's
  /// volume keys.
  Future<void> setDeviceVolume(double volume) async {
    try {
      await _channel.invokeMethod('setDeviceVolume', {'volume': volume});
    } on PlatformException {
      // Session gone; the next status says so.
    }
  }

  Future<CastStatus?> fetchStatus() async {
    try {
      return CastStatus.fromMap(await _channel.invokeMethod('getStatus'));
    } on PlatformException {
      return null;
    }
  }

  /// Ends the session; the handler's session-end path writes the place back.
  Future<void> stopCasting() async {
    try {
      await _channel.invokeMethod('stopCasting');
    } on PlatformException {
      // ignore
    }
    _setState(CastState.idle);
  }

  void dispose() {
    _stateController.close();
    _devicesController.close();
    _errorController.close();
    _statusController.close();
  }
}

/// One file of the queue as the receiver gets it.
typedef CastQueueItem = ({
  String url,
  String contentType,
  int durationMs,
  String trackTitle,
});

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

