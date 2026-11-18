import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saga/core/storage/book_download_store.dart';
import 'package:saga/core/storage/server_scope.dart';
import 'package:saga/core/storage/settings_store.dart';
import 'package:saga/features/player/finished_downloads.dart';

import 'helpers/hive_test_env.dart';

/// Remove finished downloads (GitHub #29).
///
/// The download of a book played to the end goes once the listener has moved
/// on, never while it is the book in the player: Play on a finished book
/// replays it from the files on the phone.
void main() {
  late Directory dir;
  late List<String> deleted;

  setUp(() async {
    dir = await startHiveTestEnv();
    ServerScope.debugReset();
    await SettingsStore.init(testEncKey);
    await BookDownloadStore.init(testEncKey);
    await SettingsStore.setRemoveFinishedDownloads(true);
    deleted = [];
  });
  tearDown(() => stopHiveTestEnv(dir));

  Future<List<String>> sweep(
          {String? loaded, bool Function(String)? finished}) =>
      sweepFinishedDownloads(
        loadedBook: loaded,
        isFinished: finished ?? (_) => true,
        delete: (book, tracks) async {
          deleted.add(book);
          for (final t in tracks) {
            BookDownloadStore.removeDownload(book, t);
          }
        },
      );

  test('the fate of a noted book', () {
    FinishedDownloadFate fate(
            {bool loaded = false, bool finished = true, bool has = true}) =>
        finishedDownloadFate(
            isLoaded: loaded, finishedNow: finished, hasDownload: has);
    expect(fate(), FinishedDownloadFate.remove);
    // Loaded wins over everything: the player may be about to replay it.
    expect(fate(loaded: true), FinishedDownloadFate.wait);
    expect(fate(loaded: true, finished: false), FinishedDownloadFate.wait);
    expect(fate(finished: false), FinishedDownloadFate.forget);
    expect(fate(has: false), FinishedDownloadFate.forget);
  });

  test('a finished book keeps its download while it is in the player',
      () async {
    BookDownloadStore.recordDownload('10', '11');
    await noteFinishedDownload('10');

    expect(await sweep(loaded: '10'), isEmpty);
    expect(deleted, isEmpty);
    expect(BookDownloadStore.hasDownload('10'), isTrue);
  });

  test('and loses it once another book is loaded', () async {
    BookDownloadStore.recordDownload('10', '11');
    await noteFinishedDownload('10');

    expect(await sweep(loaded: '20'), ['10']);
    expect(BookDownloadStore.hasDownload('10'), isFalse);
    // Not swept twice.
    expect(await sweep(loaded: '20'), isEmpty);
    expect(deleted, ['10']);
  });

  test('a book picked up again keeps its download for good', () async {
    BookDownloadStore.recordDownload('10', '11');
    await noteFinishedDownload('10');

    // Replayed, so no longer finished; then another book is loaded.
    expect(await sweep(loaded: '20', finished: (_) => false), isEmpty);
    // And it stays, even if it reads as finished at a later sweep.
    expect(await sweep(loaded: '20'), isEmpty);
    expect(BookDownloadStore.hasDownload('10'), isTrue);
  });

  test('nothing is noted with the setting off', () async {
    await SettingsStore.setRemoveFinishedDownloads(false);
    BookDownloadStore.recordDownload('10', '11');
    await noteFinishedDownload('10');
    await SettingsStore.setRemoveFinishedDownloads(true);

    expect(await sweep(), isEmpty);
    expect(BookDownloadStore.hasDownload('10'), isTrue);
  });

  test('turning the setting off forgets what was noted', () async {
    BookDownloadStore.recordDownload('10', '11');
    await noteFinishedDownload('10');
    await SettingsStore.setRemoveFinishedDownloads(false);
    expect(await sweep(), isEmpty);

    await SettingsStore.setRemoveFinishedDownloads(true);
    expect(await sweep(), isEmpty);
    expect(BookDownloadStore.hasDownload('10'), isTrue);
  });

  test('a book that is not downloaded is never noted', () async {
    await noteFinishedDownload('10');
    expect(SettingsStore.finishedDownloadsPending, isEmpty);
  });

  test('a failed delete is tried again at the next sweep', () async {
    BookDownloadStore.recordDownload('10', '11');
    await noteFinishedDownload('10');

    final removed = await sweepFinishedDownloads(
      loadedBook: null,
      isFinished: (_) => true,
      delete: (_, _) async => throw const FileSystemException('busy'),
    );
    expect(removed, isEmpty);
    expect(await sweep(), ['10']);
  });

  test('the noted list survives a restart', () async {
    BookDownloadStore.recordDownload('10', '11');
    await noteFinishedDownload('10');

    await coldRestartHive();
    await SettingsStore.init(testEncKey);
    await BookDownloadStore.init(testEncKey);

    expect(await sweep(), ['10']);
  });
}
