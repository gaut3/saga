import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/plex/plex_client.dart';
import 'core/providers.dart';
import 'core/theme/saga_theme.dart';
import 'features/auth/auth_screen.dart';
import 'features/auth/server_selection_screen.dart';
import 'features/main_shell.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Wire 401/403 interceptor callback: when the Plex token is rejected,
    // clear auth state and route back to the login screen.
    PlexClient.instance.onUnauthorized = () {
      ref.read(isAuthenticatedProvider.notifier).state = false;
    };

    final isAuthenticated = ref.watch(isAuthenticatedProvider);
    final serverUri = ref.watch(activeServerUriProvider);
    final themeVariant = ref.watch(sagaThemeVariantProvider);
    final t = SagaThemeData.fromVariant(themeVariant);

    // Push the active theme into the static accessor so all SagaColors.xxx
    // getters return the correct values during this build and all descendant
    // builds that follow.
    SagaColors.apply(t);

    // A server that has been chosen before but isn't answering *right now* is
    // not the same thing as an install that never had one, and only the second
    // wants the setup screen. Routing on live reachability meant opening the
    // app with no network dropped the listener on "Connect to Plex" — a screen
    // that suppresses its own back button while it is the setup step, and that
    // then failed to load a server list, because loading one needs the network
    // that isn't there. Downloaded books sat on the phone, unreachable, for as
    // long as the flight lasted.
    //
    // `machineIdentifier` is the durable half: it survives `clearServerUri`,
    // and only signing out clears it. A local-file library, when it lands,
    // joins this condition rather than replacing it — the shell must be
    // reachable whenever the phone holds something playable.
    final hasServer =
        serverUri != null || ref.watch(plexClientProvider).machineIdentifier != null;

    Widget home;
    if (!isAuthenticated) {
      home = const AuthScreen();
    } else if (!hasServer) {
      home = const ServerSelectionScreen(isSetup: true);
    } else {
      home = const MainShell();
    }

    final base = t.isDark ? ThemeData.dark() : ThemeData.light();

    return MaterialApp(
      title: 'Saga',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        colorScheme: (t.isDark
                ? const ColorScheme.dark()
                : const ColorScheme.light())
            .copyWith(
          primary: t.accent,
          secondary: t.accent,
          surface: t.surface,
          onSurface: t.fg,
        ),
        scaffoldBackgroundColor: t.bg,
        appBarTheme: AppBarTheme(
          backgroundColor: t.bg,
          foregroundColor: t.fg,
          elevation: 0,
          titleTextStyle: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: t.fg,
            letterSpacing: -0.025 * 20,
          ),
        ),
        textTheme: base.textTheme.apply(fontFamily: 'Manrope'),
        dialogTheme: DialogThemeData(backgroundColor: t.surface),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: t.surface,
          contentTextStyle: TextStyle(
            color: t.fg,
            fontFamily: 'Manrope',
            fontSize: 14,
          ),
        ),
      ),
      home: home,
    );
  }
}
