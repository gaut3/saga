import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saga/core/storage/download_store.dart';

import 'helpers/hive_test_env.dart';

void main() {
  test('a path re-bases by its downloads tail', () {
    expect(
        rebaseDownloadPath(
            '/var/mobile/Containers/Data/Application/OLD/Documents/downloads/Dune/01.m4b',
            '/var/mobile/Containers/Data/Application/NEW/Documents'),
        '/var/mobile/Containers/Data/Application/NEW/Documents/downloads/Dune/01.m4b');
    expect(rebaseDownloadPath('/somewhere/else.m4b', '/docs'), isNull);
  });

  group('DownloadStore after the app folder moved', () {
    late Directory dir;
    late Directory newDocs;

    setUp(() async {
      dir = await startHiveTestEnv();
      newDocs = await Directory('${dir.path}/NEW/Documents').create(recursive: true);
      await File('${newDocs.path}/downloads/Dune/01.m4b')
          .create(recursive: true);
      await DownloadStore.init(testEncKey, documentsDir: newDocs.path);
    });

    tearDown(() => stopHiveTestEnv(dir));

    test('finds the file in the new folder and remembers it', () async {
      // iPhone, 2026-11-16: the stored path named the folder before the
      // update, and reconcile() dropped the download as missing.
      await DownloadStore.save(
          't1', '${dir.path}/OLD/Documents/downloads/Dune/01.m4b');
      final moved = '${newDocs.path}/downloads/Dune/01.m4b';
      expect(DownloadStore.getPath('t1'), moved);
      await coldRestartHive();
      await DownloadStore.init(testEncKey, documentsDir: newDocs.path);
      expect(DownloadStore.getPath('t1'), moved, reason: 'written back');
      expect(DownloadStore.allDownloads()['t1'], moved);
    });

    test('a file that really is gone still reads as gone', () async {
      final gone = '${dir.path}/OLD/Documents/downloads/Dune/02.m4b';
      await DownloadStore.save('t2', gone);
      expect(DownloadStore.getPath('t2'), gone);
      expect(File(DownloadStore.getPath('t2')!).existsSync(), isFalse);
    });
  });
}
