import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../diagnostics/app_log.dart';

enum CastState { idle, connecting, connected }

class CastDevice {
  final String id;
  final String name;

  const CastDevice({required this.id, required this.name});
}

class CastService {
  static const _channel = MethodChannel('com.gaut3.saga/cast');

  final _stateController = StreamController<CastState>.broadcast();
  final _devicesController = StreamController<List<CastDevice>>.broadcast();
  final _errorController = StreamController<String>.broadcast();
  CastState _state = CastState.idle;
  List<CastDevice> _devices = const [];

  CastService() {
    _channel.setMethodCallHandler(_onNativeCall);
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
            _errorController.add(reason);
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
        _devicesController.add(_devices);
    }
  }

  void _setState(CastState s) {
    _state = s;
    _stateController.add(s);
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
      AppLog.log('cast', 'connecting to "${device.name}"');
      await _channel.invokeMethod('selectRoute', {'id': device.id});
    } on PlatformException catch (e) {
      AppLog.log('cast', 'selectRoute failed: ${e.code} ${e.message}');
      _errorController.add(e.message ?? e.code);
      _setState(CastState.idle);
    }
  }

  /// Loads a track onto the active Cast session. [url] must be fetchable by
  /// the Cast device itself (token in the query string, never a file:// path).
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

  /// Current playback position on the Cast device in milliseconds (0 when
  /// nothing is playing). Used to hand the position back on disconnect.
  Future<int> getCastPosition() async {
    try {
      final pos = await _channel.invokeMethod<int>('getCastPosition');
      return (pos != null && pos > 0) ? pos : 0;
    } on PlatformException {
      return 0;
    }
  }

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

final castServiceProvider = Provider<CastService>((ref) {
  final service = CastService();
  ref.onDispose(service.dispose);
  return service;
});
