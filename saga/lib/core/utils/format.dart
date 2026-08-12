import 'date_math.dart';

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

/// Listening time for the History and Home strips: "2h 5m", "45m", "<1m".
///
/// Distinct from [fmtDurationMs], which formats a book's *length* and returns
/// an empty string below a minute — for time actually listened, "<1m" is the
/// honest answer and blank is not. Home and History each carried a private
/// copy of this, character for character identical.
String fmtListenedMs(int ms) {
  final h = ms ~/ 3600000;
  final m = (ms % 3600000) ~/ 60000;
  if (h > 0) return '${h}h ${m}m';
  if (m > 0) return '${m}m';
  return '<1m';
}

String fmtTime(DateTime dt) =>
    '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

/// "Today" / "Yesterday" / "d/m/yyyy" for [dt].
///
/// Three screens had their own version. Two compared day counts, one compared
/// `today.subtract(const Duration(days: 1))` against a midnight value with `==`
/// — which on the two days a year the clocks change yields 23:00 of the day
/// before and matches nothing, quietly turning "Yesterday" into a bare date.
/// Calendar days come from [addDays], never from a [Duration].
String relativeDayLabel(DateTime dt, {DateTime? now}) {
  final day = dayOnly(dt);
  final today = dayOnly(now ?? DateTime.now());
  if (day == today) return 'Today';
  if (day == addDays(today, -1)) return 'Yesterday';
  return '${dt.day}/${dt.month}/${dt.year}';
}

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
