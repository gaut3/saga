import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum CastState { idle, connecting, connected }

class CastService {
  static const _channel = MethodChannel('com.gaut3.saga/cast');

  final _stateController = StreamController<CastState>.broadcast();
  CastState _state = CastState.idle;

  CastService() {
    _channel.setMethodCallHandler(_onNativeCall);
  }

  CastState get state => _state;
  Stream<CastState> get stateStream => _stateController.stream;

  Future<dynamic> _onNativeCall(MethodCall call) async {
    if (call.method == 'onSessionStateChanged') {
      final connected = call.arguments['connected'] as bool? ?? false;
      _setState(connected ? CastState.connected : CastState.idle);
    }
  }

  void _setState(CastState s) {
    _state = s;
    _stateController.add(s);
  }

  /// Opens the native Cast device picker dialog.
  Future<void> openDevicePicker() async {
    try {
      _setState(CastState.connecting);
      await _channel.invokeMethod('openDevicePicker');
    } on PlatformException {
      _setState(CastState.idle);
    }
  }

  /// Loads the current track onto the active Cast session.
  Future<void> loadMedia({
    required String url,
    required String title,
    required String artist,
    String artwork = '',
    int positionMs = 0,
  }) async {
    try {
      await _channel.invokeMethod('loadMedia', {
        'url': url,
        'title': title,
        'artist': artist,
        'artwork': artwork,
        'positionMs': positionMs,
      });
    } on PlatformException {
      // Session may have dropped; reset state
      _setState(CastState.idle);
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
  }
}

final castServiceProvider = Provider<CastService>((ref) {
  final service = CastService();
  ref.onDispose(service.dispose);
  return service;
});
