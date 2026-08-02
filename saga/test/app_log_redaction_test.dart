import 'package:flutter_test/flutter_test.dart';
import 'package:saga/core/diagnostics/app_log.dart';

/// The diagnostics log exists to be pasted into a public bug report, so what it
/// must never contain is the point of the whole thing.
///
/// Addresses in this file are from the documentation ranges (RFC 5737), never a
/// real one.
void main() {
  setUp(() => AppLog.clear());

  test('a bare plex.direct host leaks neither the IP nor the machine id', () {
    // Exactly how it arrives: quoted by the socket layer, no scheme in sight,
    // with the public IP encoded as dashes and the server id after it.
    AppLog.log(
      'uncaught',
      "SocketException: Failed host lookup: "
          "'203-0-113-7.424e887bd5b345088ab6c9ca262a8937.plex.direct' "
          "(OS Error: No address associated with hostname, errno = 7)",
    );
    final out = AppLog.dump();
    expect(out, isNot(contains('203-0-113-7')));
    expect(out, isNot(contains('424e887bd5b345088ab6c9ca262a8937')));
    // Still says what kind of failure it was.
    expect(out, contains('Failed host lookup'));
    expect(out, contains('plex.direct'));
  });

  test('a bare LAN address is masked', () {
    AppLog.log('plex', 'connect failed to 198.51.100.24:32400');
    expect(AppLog.dump(), isNot(contains('198.51.100.24')));
    expect(AppLog.dump(), contains('32400'));
  });

  test('a token and its host are masked in a URL', () {
    AppLog.log('plex',
        'GET https://198.51.100.24:32400/library/sections?X-Plex-Token=abc123DEF');
    final out = AppLog.dump();
    expect(out, isNot(contains('abc123DEF')));
    expect(out, isNot(contains('198.51.100.24')));
    expect(out, contains('/library/sections'));
  });

  test('the crash build id survives, since it is what symbolicates a stack', () {
    AppLog.log('uncaught', "build_id: '4f1bdaed2e6cabe9128a5ff33bf13d53'");
    expect(AppLog.dump(), contains('4f1bdaed2e6cabe9128a5ff33bf13d53'));
  });

  test('a version number is not mistaken for an address', () {
    AppLog.log('app', 'launch 1.0.15+16');
    expect(AppLog.dump(), contains('1.0.15+16'));
  });

  test('a native stack is clipped instead of eating the whole log', () {
    final stack = ['SocketException: boom', for (var i = 0; i < 60; i++) '#$i abs 0000d109'];
    AppLog.log('uncaught', stack.join('\n'));

    final lines = AppLog.dump().split('\n');
    expect(lines.length, lessThan(20));
    expect(lines.first, contains('SocketException: boom'));
    expect(lines.last, contains('more lines'));
  });
}
