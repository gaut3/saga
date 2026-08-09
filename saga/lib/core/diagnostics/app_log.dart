import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Local-only diagnostics log. No telemetry: entries are written to a small
/// rotating file in app-private storage, and nothing here ever sends them
/// anywhere. "Copy diagnostics" in Settings → About puts them on the clipboard;
/// where they go after that is the user's doing.
///
/// Entries are redacted at write time — the Plex token and any server host
/// are masked before a line ever reaches disk, so the log can never leak
/// credentials no matter how it is shared.
class AppLog {
  static const _fileName = 'saga_diagnostics.log';
  static const _maxLines = 400;

  /// A crash entry carries a native stack of 60-odd frames. Three of those and
  /// the 400-line budget is gone, which is exactly what happened: a log full of
  /// hex from one bad afternoon and no room for the week around it. The top
  /// frames are the ones worth symbolicating, so keep those and drop the rest.
  static const _maxLinesPerEntry = 12;

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
      final line = '$ts [$tag] ${_redact(_clip(message))}';
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
  ///
  /// Redacted again on the way out, not just on the way in. Entries written by
  /// an older build are still sitting in the file, and this is the last point
  /// at which anything can be done about them.
  static String dump() => _buffer.map(_redact).join('\n');

  static Future<void> clear() async {
    _buffer.clear();
    try {
      await _file?.writeAsString('');
    } catch (_) {}
  }

  /// Trims a multi-line entry to its first [_maxLinesPerEntry] lines, noting
  /// what was dropped so the entry doesn't read as a complete stack.
  static String _clip(String message) {
    final lines = message.split('\n');
    if (lines.length <= _maxLinesPerEntry) return message;
    final dropped = lines.length - _maxLinesPerEntry;
    return '${lines.take(_maxLinesPerEntry).join('\n')}\n'
        '  … $dropped more lines';
  }

  /// Strips credentials and server addresses so no entry can identify or
  /// authenticate against the user's server: Plex tokens are masked and any
  /// host is replaced with bullets (same convention as the redact-server-address
  /// display toggle).
  ///
  /// A host does not need a `http://` in front of it to identify someone. The
  /// rules below run in order, narrowest first, because a plex.direct name
  /// carries *two* secrets at once: the label is the server's public IP with
  /// dots swapped for dashes, and the one after it is the machine identifier.
  /// Errors thrown by the socket layer quote that name on its own, with no
  /// scheme anywhere near it, which is how one reached a log that was supposed
  /// to be safe to paste into a public issue.
  ///
  /// Deliberately not masked: the 32-hex `build_id` in a crash dump, which is
  /// the same for every install of a release and is what makes the stack
  /// symbolicatable. It is only ever quoted as `build_id: '…'`, so the rules
  /// here are written to leave a bare hex run alone.
  static String _redact(String input) {
    var out = input.replaceAll(
        RegExp(r'X-Plex-Token=[^&\s"]+'), 'X-Plex-Token=••••');
    // The token as plex.tv itself spells it. A malformed auth response ends up
    // quoted inside a FormatException (which includes the source text near the
    // error), and that carries `"authToken":"…"` — a shape the query-parameter
    // rule above doesn't know.
    out = out.replaceAllMapped(
        RegExp(r'''(authToken["']?\s*[=:]\s*["']?)([^"'\s,}]+)''',
            caseSensitive: false),
        (m) => '${m[1]}••••');
    // Whole plex.direct name: <ip-with-dashes>.<machine id>.plex.direct
    out = out.replaceAll(
      RegExp(r'[\w-]+\.[\w-]+\.plex\.direct', caseSensitive: false),
      '••••••••.plex.direct',
    );

    // Hosts the socket layer names on its own, in the three shapes Dart
    // writes:
    //   SocketException: Failed host lookup: 'plex.example.com' (OS Error: …)
    //   SocketException: Connection refused (…), address = plex.example.com, …
    //   SocketException: HTTP connection timed out after 0:00:10.000000,
    //     host: plex.example.com, port: 32400
    // The IPv4 rule below only ever caught the first kind of address. Someone
    // running their server on a custom domain or reachable over IPv6 was still
    // pasting their own hostname into a public issue — the same gap as the bare
    // plex.direct name, one shape further out. The third shape comes from the
    // SDK's connection-timeout path (dio sets `HttpClient.connectionTimeout`
    // from `connectTimeout`), which quotes the host after `host:` — the word
    // `address` never appears in it.
    //
    // Both rules leave alone anything a narrower rule above has already
    // bulleted, so `••••••••.plex.direct` keeps saying *what kind* of host
    // failed rather than collapsing to an anonymous blob.
    String maskUnlessHandled(Match m) {
      if (m[2]!.contains('•')) return m[0]!;
      // The quoted form captures its closing quote; the bare form has no
      // third group. Asking for one that isn't there throws, and log() catches
      // everything — which turns a broken rule into a silently missing entry.
      final tail = m.groupCount >= 3 ? m[3]! : '';
      return '${m[1]}••••••••$tail';
    }

    out = out.replaceAllMapped(
        RegExp("(host lookup:\\s*')([^']*)(')", caseSensitive: false),
        maskUnlessHandled);
    out = out.replaceAllMapped(
        RegExp(r'(\b(?:address|host)\s*[=:]\s*)([^\s,)]+)',
            caseSensitive: false),
        maskUnlessHandled);

    // Scheme-prefixed host, including the bracketed IPv6 form — `[::1]:32400`
    // stopped the old pattern at the first colon and left the address showing.
    out = out.replaceAllMapped(
      RegExp(r'(https?://)(\[[^\]\s]+\]|[^/\s:"]+)'),
      (m) => '${m[1]}••••••••',
    );
    // Bare addresses: bracketed IPv6, dotted IPv4, and the dash-encoded form
    // Plex uses. The IPv6 rule requires a colon inside the brackets, so it
    // can't swallow the `[tag]` every log line starts with.
    out = out.replaceAll(
        RegExp(r'\[[0-9a-fA-F:]*:[0-9a-fA-F:]*\]'), '••••••••');
    out = out.replaceAll(
        RegExp(r'\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b'), '••••••••');
    out = out.replaceAll(
        RegExp(r'\b\d{1,3}-\d{1,3}-\d{1,3}-\d{1,3}\b'), '••••••••');
    out = out.replaceAll(
        RegExp(r'machineIdentifier[=:]\s*[\w-]+', caseSensitive: false),
        'machineIdentifier=••••');
    return out;
  }
}
