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

  test('a bare custom hostname is masked, not just a bare IP', () {
    // Not everyone reaches their server by IP or plex.direct. The old rules
    // knew those two shapes and nothing else, so someone on their own domain
    // pasted it straight into a public issue.
    AppLog.log(
      'uncaught',
      "SocketException: Failed host lookup: 'plex.example.com' "
          "(OS Error: No address associated with hostname, errno = 7)",
    );
    final out = AppLog.dump();
    expect(out, isNot(contains('plex.example.com')));
    expect(out, contains('Failed host lookup'));
  });

  test('a host named in the address= form is masked', () {
    AppLog.log(
      'plex',
      'SocketException: Connection refused (OS Error: Connection refused, '
          'errno = 111), address = plex.example.com, port = 32400',
    );
    final out = AppLog.dump();
    expect(out, isNot(contains('plex.example.com')));
    // The port is not identifying and says which service failed.
    expect(out, contains('32400'));
  });

  test('an IPv6 address is masked, in a URL and on its own', () {
    AppLog.log('plex', 'GET http://[2001:db8::7334]:32400/identity failed');
    AppLog.log('plex', 'connect failed, address = [2001:db8::7334]');
    final out = AppLog.dump();
    expect(out, isNot(contains('2001:db8')));
    expect(out, contains('/identity'));
  });

  test('masking a host does not erase which kind of host it was', () {
    // plex.direct is handled by a narrower rule above the generic ones. The
    // generic rules must leave its work alone rather than flattening the whole
    // quoted value — "a plex.direct lookup failed" is the useful part.
    AppLog.log(
      'uncaught',
      "SocketException: Failed host lookup: "
          "'203-0-113-7.424e887bd5b345088ab6c9ca262a8937.plex.direct'",
    );
    final out = AppLog.dump();
    expect(out, isNot(contains('203-0-113-7')));
    expect(out, isNot(contains('424e887bd5b345088ab6c9ca262a8937')));
    expect(out, contains('plex.direct'));
  });

  test('the SDK connection-timeout shape does not leak a custom host', () {
    // Thrown by dart:io when HttpClient.connectionTimeout fires (dio sets it
    // from connectTimeout, which every Dio here configures). The word
    // "address" never appears in it — the host arrives after `host:`.
    AppLog.log(
      'playback',
      'SocketException: HTTP connection timed out after 0:00:10.000000, '
          'host: audiobooks.example.org, port: 32400',
    );
    final out = AppLog.dump();
    expect(out, isNot(contains('audiobooks.example.org')));
    expect(out, contains('connection timed out'));
    expect(out, contains('32400'));
  });

  test('a plex.tv auth token quoted into an error body is masked', () {
    // A malformed auth response ends up quoted inside a FormatException,
    // which includes the source text near the error — authToken and all.
    AppLog.log(
      'auth',
      'sign-in failed: FormatException: Unexpected character (at character 40) '
          '{"authToken":"xyzSECRET123","user":{}}<html>',
    );
    final out = AppLog.dump();
    expect(out, isNot(contains('xyzSECRET123')));
    expect(out, contains('authToken'));
    expect(out, contains('FormatException'));
  });

  test('a machine identifier is masked', () {
    AppLog.log('plex',
        'selected server machineIdentifier: 424e887bd5b345088ab6c9ca262a8937');
    expect(AppLog.dump(),
        isNot(contains('424e887bd5b345088ab6c9ca262a8937')));
  });

  test('the log tag is not mistaken for an address', () {
    // Every line is "<timestamp> [tag] message" and the IPv6 rule looks for
    // bracketed text — it must need a colon inside to fire.
    AppLog.log('cast', 'session ended');
    expect(AppLog.dump(), contains('[cast]'));
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
