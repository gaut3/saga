import 'package:flutter_test/flutter_test.dart';
import 'package:saga/core/diagnostics/app_log.dart';

void main() {
  final cutoff = DateTime.parse('2026-08-08T12:00:00');

  test('stale entries go, including their untimestamped stack lines', () {
    final lines = [
      '2026-06-19T18:06:02.071 [uncaught] SocketException: host lookup failed',
      '*** *** *** *** ***',
      "build_id: '4f1bdaed'",
      '    #00 abs 0000d109ed1bdeeb virt 000000000021beeb',
      '',
      '2026-08-10T09:00:00.000 [app] launch 1.1.1+19',
      '    #00 stack line belonging to a fresh entry',
    ];
    expect(AppLog.staleCount(lines, cutoff), 5);
  });

  test('all fresh: nothing pruned', () {
    expect(
      AppLog.staleCount(['2026-08-10T09:00:00.000 [app] launch'], cutoff),
      0,
    );
  });

  test('all stale: everything pruned', () {
    final lines = [
      '2026-06-19T18:06:02.071 [uncaught] old error',
      '    #00 stack line',
    ];
    expect(AppLog.staleCount(lines, cutoff), 2);
  });

  test('recent: one tag, newest first, redacted, capped', () {
    AppLog.log('sync', 'one');
    AppLog.log('playback', 'other');
    AppLog.log('sync', 'two from http://192.168.1.5:32400');
    AppLog.log('sync', 'three');
    final lines = AppLog.recent('sync', count: 2);
    expect(lines, hasLength(2));
    expect(lines.first, endsWith('[sync] three'));
    expect(lines.last, contains('[sync] two'));
    expect(lines.last, isNot(contains('192.168')));
  });

  test('empty log', () {
    expect(AppLog.staleCount([], cutoff), 0);
  });
}
