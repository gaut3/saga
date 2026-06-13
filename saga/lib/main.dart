import 'dart:async';
import 'dart:convert';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app.dart';
import 'core/audio/audio_level.dart';
import 'core/diagnostics/app_log.dart';
import 'core/mark_motion.dart';
import 'core/plex/plex_api.dart';
import 'core/plex/plex_client.dart';
import 'core/storage/artwork_cache.dart';
import 'core/storage/bookmark_store.dart';
import 'core/storage/book_download_store.dart';
import 'core/storage/chapter_store.dart';
import 'core/storage/completed_books_store.dart';
import 'core/storage/custom_collection_store.dart';
import 'core/storage/download_store.dart';
import 'core/storage/listen_days_store.dart';
import 'core/storage/listening_history_store.dart';
import 'core/storage/named_bookmark_store.dart';
import 'core/storage/playback_log_store.dart';
import 'core/storage/settings_store.dart';
import 'core/storage/timeline_queue_store.dart';
import 'core/storage/want_to_read_store.dart';
import 'features/player/player_provider.dart';
import 'features/player/player_service.dart';

Future<void> main() async {
  // Everything (including ensureInitialized and runApp) must live in the same
  // zone, so the guarded zone wraps the whole startup. Uncaught errors are
  // written to the local diagnostics log — never transmitted anywhere.
  await runZonedGuarded(_run, (Object e, StackTrace st) {
    AppLog.log('uncaught', '$e\n$st');
  });
}

Future<void> _run() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Framework errors: keep Flutter's default console reporting, and append a
  // redacted copy to the local diagnostics log for "Copy diagnostics".
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    AppLog.log('flutter', '${details.exception}\n${details.stack ?? ''}');
  };

  await AppLog.init();

  try {
    await Hive.initFlutter();
    final hiveKey = await _loadHiveKey();
    await BookmarkStore.init(hiveKey);
    await CustomCollectionStore.init(hiveKey);
    await BookDownloadStore.init(hiveKey);
    await ChapterStore.init(hiveKey);
    await CompletedBooksStore.init(hiveKey);
    await DownloadStore.init(hiveKey);
    await ListeningHistoryStore.init(hiveKey);
    await ListenDaysStore.init(hiveKey);
    await NamedBookmarkStore.init(hiveKey);
    await PlaybackLogStore.init(hiveKey);
    await SettingsStore.init(hiveKey);
    await TimelineQueueStore.init(hiveKey);
    await WantToReadStore.init(hiveKey);
    await ArtworkCache.init();

    // Load the persisted now-playing mark animation choice.
    initMarkMotion();

    final client = await PlexClient.init();

    final service = await AudioService.init(
      builder: () => AudioPlayerService(PlexApi(client)),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.gaut3.saga.channel.audio',
        androidNotificationChannelName: 'Saga Playback',
        androidStopForegroundOnPause: false,
        androidResumeOnClick: true,
        androidNotificationIcon: 'drawable/ic_launcher_monochrome',
      ),
    );

    setPlayerServiceInstance(service);

    // Start listening for the real-loudness tap (drives the playing visualizer).
    AudioLevel.instance.setDelay(SettingsStore.animationSyncDelayMs);
    AudioLevel.instance.start();

    // Retention: the Day tab only renders recent days, so playback-log events
    // older than 12 months are dead weight. Prune before session reconciliation
    // so a reconcile never resurrects a just-pruned book.
    final pruned = await PlaybackLogStore.pruneOldEvents();
    if (pruned > 0) {
      AppLog.log('storage', 'pruned $pruned playback-log events (>12 months)');
    }

    _reconcileDanglingSessions();

    runApp(const ProviderScope(child: App()));
  } catch (e, st) {
    AppLog.log('startup', 'failed to start: $e\n$st');
    runApp(const _ErrorApp());
  }
}

void _reconcileDanglingSessions() {
  for (final bookKey in PlaybackLogStore.bookRatingKeys()) {
    final log = PlaybackLogStore.getLog(bookKey);
    if (log.isEmpty) continue;
    final last = log.last;
    if (last.type != 'play') continue;
    // The session was never closed (app was killed). Close it now using the
    // bookmark's savedAt as the closest approximation of when playback stopped.
    final bookmark = BookmarkStore.load(bookKey);
    final closeTime = bookmark?.savedAt ?? last.timestamp;
    PlaybackLogStore.log(
      bookRatingKey: bookKey,
      event: AudioLogEvent(
        type: 'pause',
        trackRatingKey: last.trackRatingKey,
        positionMs: bookmark?.positionMs ?? last.positionMs,
        timestamp: closeTime,
      ),
    );
  }
}

Future<List<int>> _loadHiveKey() async {
  const storage = FlutterSecureStorage();
  const keyName = 'hive_enc_key';
  final existing = await storage.read(key: keyName);
  if (existing != null) {
    return base64Decode(existing);
  }
  final key = Hive.generateSecureKey();
  await storage.write(key: keyName, value: base64Encode(key));
  return key;
}

class _ErrorApp extends StatelessWidget {
  const _ErrorApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                SizedBox(height: 16),
                Text(
                  'Failed to start',
                  style: TextStyle(
                      color: Colors.redAccent,
                      fontSize: 22,
                      fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 12),
                Text(
                  'Something went wrong during startup. '
                  'Try restarting the app. If the problem persists, clear app data from Settings.',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
