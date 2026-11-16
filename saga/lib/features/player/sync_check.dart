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

/// What a check found: the decision, and the server's place it was made
/// from (null when Plex knows nothing).
///
/// [trackRatingKey] names the server's file, so a start point never relies on
/// the server's file order matching the cached one.
typedef ServerCheck = ({
  SyncDecision decision,
  ServerPosition? server,
  String? trackRatingKey,
});

/// One check of a book against the server, on an in-app open or play. Logs
/// one line, which says what it would do (shadow) or what it does (live):
///
///   shadow book 23340 (open): would take Plex's place, with Undo · Plex
///   35 min 0 s ahead, newer by 4 min 10 s · answered in 420 ms · clock +1 s
///
/// [waited] says whether the caller is holding audio for the answer (live,
/// and not a downloaded book playing). Then an answer later than
/// [syncWaitLimit] is noted as dropped: the caller has played the local
/// place by the time it arrives.
///
/// It reads and logs, and nothing else: no seek, no save, no load. A test
/// pins that this file can't reach any of them. What happens to the answer
/// is the caller's business.
Future<ServerCheck?> checkServerPlace({
  required PlexApi api,
  required String bookKey,
  required String trigger,
  required LocalPlace? local,
  required bool finished,
  required bool downloaded,
  required bool live,
  required bool waited,
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

    final late = took > syncWaitLimit;
    final timing = !waited && downloaded
        ? 'downloaded: ${live ? 'did' : 'live would'} not wait'
        : !live
            ? 'answered in ${took.inMilliseconds} ms'
                '${late ? ': too late, live would play the local place' : ''}'
            : 'answered in ${took.inMilliseconds} ms'
                '${late ? ': too late, the local place played' : ''}';
    final verb = live && waited && !late ? 'will' : 'would';
    AppLog.log(
        'sync',
        '${live ? 'live' : 'shadow'} book $bookKey ($trigger): $verb '
            '${decision.action.wouldDo} · ${decision.reason} · $timing'
            '${skew == null ? '' : ' · clock ${_signedSeconds(skew)}'}');
    return (
      decision: decision,
      server: server,
      trackRatingKey:
          server == null ? null : read.tracks[server.fileIndex].ratingKey,
    );
  } catch (e) {
    AppLog.log('sync',
        '${live ? 'live' : 'shadow'} book $bookKey ($trigger): no answer ($e)');
    return null;
  }
}

String _signedSeconds(Duration d) {
  final s = (d.inMilliseconds / 1000).round();
  return '${s >= 0 ? '+' : ''}$s s';
}
