String fmtDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

String fmtDurationMs(int? ms) {
  if (ms == null || ms <= 0) return '';
  final h = ms ~/ 3600000;
  final m = (ms % 3600000) ~/ 60000;
  if (h > 0 && m > 0) return '${h}h ${m}m';
  if (h > 0) return '${h}h';
  return '${m}m';
}

String fmtPositionMs(int ms) {
  final h = ms ~/ 3600000;
  final m = (ms % 3600000) ~/ 60000;
  final s = (ms % 60000) ~/ 1000;
  if (h > 0) {
    return '${h}h ${m.toString().padLeft(2, '0')}m ${s.toString().padLeft(2, '0')}s';
  }
  return '${m}m ${s.toString().padLeft(2, '0')}s';
}

String fmtTime(DateTime dt) =>
    '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

/// Replaces the host of [uri] with bullets for privacy display.
/// Protocol and port remain visible so the tile still reads as "connected".
String maskAddress(String uri) {
  try {
    final parsed = Uri.parse(uri);
    return parsed.replace(host: '••••••••').toString();
  } catch (_) {
    return '[address hidden]';
  }
}
