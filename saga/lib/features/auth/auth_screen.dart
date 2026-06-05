import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  Future<void> _startLogin() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final auth = ref.read(plexAuthProvider);
      final pin = await auth.requestPin();
      await auth.openAuthUrl(pin);

      setState(() {
        _loading = false;
        _waitingForAuth = true;
      });

      final token = await auth.pollForToken(pin);

      if (!mounted) return;

      if (token != null) {
        ref.read(isAuthenticatedProvider.notifier).state = true;
      } else {
        setState(() {
          _waitingForAuth = false;
          _error = 'Authentication timed out. Please try again.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _waitingForAuth = false;
        _error = 'Error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SagaColors.bg,
      body: SafeArea(
        child: Center(
          child: Padding(
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
                ] else
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _startLogin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: SagaColors.accent,
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
