import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/diagnostics/app_log.dart';
import '../../core/plex/plex_auth.dart';
import '../../core/providers.dart';
import '../../core/theme/saga_theme.dart';
import '../../shared/widgets/saga_mark.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  bool _loading = false;
  bool _waitingForAuth = false;
  String? _error;

  /// Bumped by each sign-in, and by success: a poll from an older one stops
  /// at its next tick and its result is ignored.
  int _attempt = 0;
  int _activePolls = 0;

  /// The plex.tv/link fallback, offered once the browser has had a while.
  /// The browser flow can fail to come back (a browser that won't open the
  /// Plex page, a phone that doesn't hand the result back, signing in on a
  /// different device); the code works from any browser.
  static const _offerCodeAfter = Duration(seconds: 15);
  Timer? _offerTimer;
  bool _offerCode = false;
  bool _requestingCode = false;
  String? _linkCode;
  String? _codeError;

  @override
  void dispose() {
    _offerTimer?.cancel();
    super.dispose();
  }

  Future<void> _startLogin() async {
    final attempt = ++_attempt;
    _offerTimer?.cancel();
    setState(() {
      _loading = true;
      _error = null;
      _offerCode = false;
      _linkCode = null;
      _codeError = null;
    });

    try {
      final auth = ref.read(plexAuthProvider);
      final pin = await auth.requestPin();
      await auth.openAuthUrl(pin);

      if (!mounted) return;
      setState(() {
        _loading = false;
        _waitingForAuth = true;
      });
      _offerTimer = Timer(_offerCodeAfter, () {
        if (mounted && attempt == _attempt) setState(() => _offerCode = true);
      });

      await _poll(pin, attempt, const Duration(minutes: 5));
    } catch (e) {
      // Details go to the redacted log, never the screen: a raw error here can
      // quote the plex.tv response body — which is where the auth token lives —
      // and the sign-in screen is exactly what ends up in a bug-report
      // screenshot.
      AppLog.log('auth', 'sign-in failed: $e');
      if (!mounted || attempt != _attempt) return;
      _offerTimer?.cancel();
      setState(() {
        _loading = false;
        _waitingForAuth = false;
        _offerCode = false;
        _error = 'Couldn\'t sign in. Check your connection and try again.';
      });
    }
  }

  /// A second PIN, the short kind plex.tv/link takes, polled beside the
  /// browser's: whichever is completed first signs in.
  Future<void> _useCode() async {
    final attempt = _attempt;
    setState(() {
      _requestingCode = true;
      _codeError = null;
    });
    try {
      final pin = await ref.read(plexAuthProvider).requestPin(strong: false);
      if (!mounted || attempt != _attempt) return;
      setState(() {
        _requestingCode = false;
        _linkCode = pin.code;
      });
      // Inside the code's own 15 minutes.
      await _poll(pin, attempt, const Duration(minutes: 10));
    } catch (e) {
      AppLog.log('auth', 'sign-in code failed: $e');
      if (!mounted || attempt != _attempt) return;
      setState(() {
        _requestingCode = false;
        _codeError = 'Couldn\'t get a code. Check your connection and try again.';
      });
    }
  }

  Future<void> _poll(PlexPinResult pin, int attempt, Duration timeout) async {
    _activePolls++;
    final String? token;
    try {
      token = await ref.read(plexAuthProvider).pollForToken(
            pin,
            timeout: timeout,
            isCancelled: () => !mounted || attempt != _attempt,
          );
    } finally {
      _activePolls--;
    }
    if (!mounted || attempt != _attempt) return;

    if (token != null) {
      _attempt++; // stops the other poll
      _offerTimer?.cancel();
      ref.read(isAuthenticatedProvider.notifier).state = true;
    } else if (_activePolls == 0 && !_requestingCode) {
      _offerTimer?.cancel();
      setState(() {
        _waitingForAuth = false;
        _offerCode = false;
        _linkCode = null;
        _error = 'Authentication timed out. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SagaColors.bg,
      body: SafeArea(
        child: Center(
          // Scrolls: the code fallback adds to the column, and at a large text
          // size on a small phone it no longer fits.
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SagaLockup(wordmarkSize: 44),
                const SizedBox(height: 16),
                Text(
                  'your audiobooks, beautifully.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: SagaColors.fgMuted,
                    letterSpacing: -0.01 * 14,
                  ),
                ),
                const SizedBox(height: 56),
                if (_waitingForAuth) ...[
                  CircularProgressIndicator(color: SagaColors.accent),
                  const SizedBox(height: 20),
                  Text(
                    'Complete sign-in in your browser.\nWaiting…',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 14,
                      color: SagaColors.fgMuted,
                    ),
                  ),
                  if (_linkCode != null)
                    _LinkCode(
                      code: _linkCode!,
                      onOpen: () => ref.read(plexAuthProvider).openLinkPage(),
                    )
                  else if (_offerCode) ...[
                    const SizedBox(height: 28),
                    TextButton(
                      onPressed: _requestingCode ? null : _useCode,
                      style: TextButton.styleFrom(
                          foregroundColor: SagaColors.accentText),
                      child: Text(
                        _requestingCode
                            ? 'Getting a code…'
                            : 'Taking a while? Sign in with a code instead',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  if (_codeError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _codeError!,
                      style: const TextStyle(color: Colors.redAccent),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ] else
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _startLogin,
                      style: ElevatedButton.styleFrom(
                        // Full-width filled button — accentDim, not accent.
                        backgroundColor: SagaColors.accentDim,
                        foregroundColor: SagaColors.accentFg,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                      ),
                      child: _loading
                          ? SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: SagaColors.accentFg,
                              ),
                            )
                          : Text(
                              'Sign in with Plex',
                              style: TextStyle(
                                fontFamily: 'Manrope',
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The plex.tv/link code, big enough to read off this phone onto another
/// device's keyboard.
class _LinkCode extends StatelessWidget {
  const _LinkCode({required this.code, required this.onOpen});

  final String code;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(
      fontFamily: 'Manrope',
      fontSize: 14,
      color: SagaColors.fgMuted,
    );
    return Column(
      children: [
        const SizedBox(height: 32),
        Text(
          'Or go to plex.tv/link on any device and enter this code:',
          textAlign: TextAlign.center,
          style: muted,
        ),
        const SizedBox(height: 12),
        Text(
          code,
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 34,
            fontWeight: FontWeight.w700,
            letterSpacing: 8,
            color: SagaColors.fg,
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: onOpen,
          style: TextButton.styleFrom(foregroundColor: SagaColors.accentText),
          child: const Text(
            'Open plex.tv/link',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
