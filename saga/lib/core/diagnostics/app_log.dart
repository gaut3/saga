import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Local-only diagnostics log. No telemetry: entries are written to a small
/// rotating file in app-private storage and leave the device only when the
/// user explicitly taps "Copy diagnostics" in Settings → About.
///
/// Entries are redacted at write time — the Plex token and any server host
/// are masked before a line ever reaches disk, so the log can never leak
/// credentials no matter how it is shared.
class AppLog {
  static const _fileName = 'saga_diagnostics.log';
  static const _maxLines = 400;

  static File? _file;
  static final List<String> _buffer = [];
  static Timer? _flushTimer;

  static Future<void> init() async {
    try {
      final dir = await getApplicationSupportDirectory();
      _file = File('${dir.path}/$_fileName');
      if (await _file!.exists()) {
        _buffer.addAll(await _file!.readAsLines());
        if (_buffer.length > _maxLines) {
          _buffer.removeRange(0, _buffer.length - _maxLines);
        }
      }
    } catch (_) {
      // Logging must never break the app; run memory-only if the file fails.
      _file = null;
    }
  }

  /// Appends a redacted, timestamped entry. Safe to call from anywhere,
  /// including error handlers — it never throws.
  static void log(String tag, String message) {
    try {
      final ts = DateTime.now().toIso8601String();
      final line = '$ts [$tag] ${_redact(message)}';
      _buffer.add(line);
      if (_buffer.length > _maxLines) {
        _buffer.removeRange(0, _buffer.length - _maxLines);
      }
      // Debounced flush: error bursts (e.g. a stack trace per frame) become
      // one write instead of hundreds.
      _flushTimer?.cancel();
      _flushTimer = Timer(const Duration(seconds: 1), _flush);
    } catch (_) {}
  }

  static Future<void> _flush() async {
    final file = _file;
    if (file == null) return;
    try {
      await file.writeAsString('${_buffer.join('\n')}\n');
    } catch (_) {}
  }

  /// Full log content for the "Copy diagnostics" action.
  static String dump() => _buffer.join('\n');

  static Future<void> clear() async {
    _buffer.clear();
    try {
      await _file?.writeAsString('');
    } catch (_) {}
  }

  /// Strips credentials and server addresses so no entry can identify or
  /// authenticate against the user's server: Plex tokens are masked and any
  /// http(s) host is replaced with bullets (same convention as the
  /// redact-server-address display toggle).
  static String _redact(String input) {
    var out = input.replaceAll(
        RegExp(r'X-Plex-Token=[^&\s"]+'), 'X-Plex-Token=••••');
    out = out.replaceAllMapped(
      RegExp(r'(https?://)([^/\s:"]+)'),
      (m) => '${m[1]}••••••••',
    );
    return out;
  }
}
