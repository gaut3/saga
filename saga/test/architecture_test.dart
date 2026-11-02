// Rules from CLAUDE.md's "Standing principles", asserted against the source.
//
// Each of these was a shipped bug, and each fix left behind a rule that only
// held while someone remembered it. Checking the source is crude, but these are
// mistakes a behavioural test can't see: a `Duration(days:)` is only wrong on
// the two DST nights a year, and an unscoped store is only wrong once a second
// server is added. The checks are deliberately simple patterns — if one of
// them misfires, add an exception with a reason rather than making it clever.
//
// Run from `saga/` (as `flutter test` is), so paths are relative to it.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every Dart file under `lib/`.
List<File> _libFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

/// The file's code with comment-only lines dropped, so that *documenting* a
/// rule doesn't trip it.
String _code(File f) => f
    .readAsLinesSync()
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

/// Forward slashes, so paths compare the same on Windows.
String _path(File f) => f.path.replaceAll(r'\', '/');

/// The files whose code contains [pattern], minus [allowed].
List<String> _offenders(Pattern pattern, {Set<String> allowed = const {}}) => [
      for (final f in _libFiles())
        if (!allowed.contains(_path(f)) && _code(f).contains(pattern))
          _path(f),
    ];

void main() {
  test('calendar days are counted with DateTime, never Duration(days:)', () {
    // `Duration(days: N)` is N×24h, so across a DST change it lands at 23:00
    // or 01:00 the wrong side of midnight — the 13-week heatmap's zero totals
    // and the Day tab's one-day-early exit. Use `addDays`/`DateTime(y, m, d+N)`
    // from core/utils/date_math.dart.
    expect(_offenders(RegExp(r'Duration\(\s*days\s*:')), isEmpty);
  });

  test('only startBook() loads a book', () {
    // "Load a book and play it" was hand-written at eight sites and four forgot
    // the book's saved speed. Add a `BookStartPoint`, not a ninth copy.
    expect(
      _offenders('.loadBook(',
          allowed: {'lib/features/player/book_launch.dart'}),
      isEmpty,
    );
  });

  test('every store that files by rating key goes through ServerScope', () {
    // A Plex ratingKey is unique only within one server, so a store keyed by
    // it alone hands one server's position to another server's book 12345.
    final exempt = {
      // Keys are calendar days. The day's finished-books list carries a bare
      // rating key only to dedupe itself, and only feeds whether the day
      // counts as active — a cross-server collision can't move a position or
      // hide a finish (CompletedBooksStore, which is scoped, owns those).
      'lib/core/storage/listening_history_store.dart',
      // Validates the shape of exported records; every write goes through the
      // stores above, which scope it.
      'lib/core/storage/progress_backup.dart',
    };
    final storage = Directory('lib/core/storage')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    final unscoped = [
      for (final f in storage)
        if (!exempt.contains(_path(f)) &&
            _code(f).contains(RegExp(r'ratingKey|\brk\b')) &&
            !_code(f).contains('ServerScope'))
          _path(f),
    ];
    expect(unscoped, isEmpty,
        reason: 'new per-book stores must key through ServerScope.key — '
            'or be exempted here, with the reason');
    for (final path in exempt) {
      expect(File(path).existsSync(), isTrue,
          reason: '$path is exempted but gone — drop the exemption');
    }
  });

  test('messages use showSagaToast, not a SnackBar', () {
    // A SnackBar mounts in the tab's Scaffold, under the nav pill and mini
    // player (`extendBody: true`), and not at all over the full-screen player.
    // The toast goes in the root overlay and pads itself.
    expect(_offenders(RegExp(r'\bSnackBar\(')), isEmpty);
  });

  test('the app names no host beyond the ones the privacy policy lists', () {
    // The prime directive: plex.tv, the user's own server (whose address is
    // discovered, never written down), and the opt-in update check. A new
    // host here is a product decision and a privacy-policy change, not an
    // implementation detail. github.com is only ever opened in the browser.
    const allowed = {
      'plex.tv',
      'app.plex.tv',
      'api.github.com',
      'github.com',
    };
    final url = RegExp(r'''['"]https?://([^/'"$:\s]+)''');
    final unexpected = <String>[
      for (final f in _libFiles())
        for (final m in url.allMatches(_code(f)))
          if (!allowed.contains(m.group(1))) '${_path(f)}: ${m.group(1)}',
    ];
    expect(unexpected, isEmpty);
  });
}
