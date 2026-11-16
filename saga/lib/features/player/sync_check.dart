import '../../core/diagnostics/app_log.dart';
import '../../core/plex/plex_api.dart';
import '../../core/sync/sync_mode.dart';
import 'server_position.dart';
import 'sync_decision.dart';

/// How long an in-app open or play waits for the server before it plays
/// the local place and drops the answer (sync design rule 1).
const syncWaitLimit = Duration(milliseconds: 1500);

/// The newest clock skew measured against the server, for developer
/// options: server ahead of the phone when positive.
Duration? lastMeasuredSkew;

/// One check of a book against the server, on an in-app open or play.
///
/// In shadow mode (build step 5) it only reads and logs what it would do:
///
///   shadow book 23340 (open): would apply · Plex 35 min ahead, newer by
///   4 min · answered in 420 ms · clock +1 s
///
/// It never waits for the answer (audio doesn't wait on a shadow), but says
/// when live mode wouldn't have: past [syncWaitLimit], or a downloaded
/// book, which never waits on the server.
///
/// It reads and logs, and nothing else: no seek, no save, no load. A test
/// pins that this file can't reach any of them.
Future<SyncDecision?> checkServerPlace({
  required PlexApi api,
  required String bookKey,
  required String trigger,
  required LocalPlace? local,
  required bool finished,
  required bool downloaded,
}) async {
  final sentAt = DateTime.now();
  try {
    final read = await api.fetchBookProgress(bookKey);
    final receivedAt = DateTime.now();
    final took = receivedAt.difference(sentAt);
    final server = resolveServerPosition([
      for (final t in read.tracks)
        (
          durationMs: t.durationMs,
          viewOffsetMs: t.viewOffsetMs,
          lastViewedAt: t.lastViewedAt,
        ),
    ]);
    final decision =
        decideSync(local: local, server: server, localFinished: finished);
    final serverDate = read.serverDate;
    final skew = serverDate == null
        ? null
        : measureSkew(
            sentAt: sentAt, receivedAt: receivedAt, serverDate: serverDate);
    if (skew != null) lastMeasuredSkew = skew;

    final timing = downloaded
        ? 'downloaded: live would not wait'
        : took > syncWaitLimit
            ? 'answered in ${took.inMilliseconds} ms: too late, live would '
                'play the local place'
            : 'answered in ${took.inMilliseconds} ms';
    AppLog.log(
        'sync',
        'shadow book $bookKey ($trigger): would '
            '${decision.action.wouldDo} · ${decision.reason} · $timing'
            '${skew == null ? '' : ' · clock ${_signedSeconds(skew)}'}');
    return decision;
  } catch (e) {
    AppLog.log('sync', 'shadow book $bookKey ($trigger): no answer ($e)');
    return null;
  }
}

String _signedSeconds(Duration d) {
  final s = (d.inMilliseconds / 1000).round();
  return '${s >= 0 ? '+' : ''}$s s';
}
