import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/saga_theme.dart';

/// The one line that explains why the rest of the library isn't here.
///
/// At the bottom of content, not the top: whatever the listener can still use
/// is the point of the screen, and a banner over it would make a working app
/// look broken. Extracted from Home when the other library tabs gained
/// offline bodies of their own — one implementation, so the wording and the
/// recovery buttons can't drift apart.
class OfflineNote extends ConsumerWidget {
  /// Null uses the default wording, which fits screens showing local content.
  final String? message;

  /// Home passes its server-selection flow; the tabs omit it (that flow needs
  /// plex.tv, and Home is where it lives).
  final VoidCallback? onSelectServer;

  static const _defaultMessage =
      "Your server isn't reachable — showing what's on this phone.";

  const OfflineNote({super.key, this.message, this.onSelectServer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(sagaThemeVariantProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message ?? _defaultMessage,
            style: TextStyle(color: SagaColors.fgMuted, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton(
                onPressed: () => ref.invalidate(activeLibraryKeyProvider),
                style: TextButton.styleFrom(
                    foregroundColor: SagaColors.accentText),
                child: const Text('Try again'),
              ),
              if (onSelectServer != null)
                TextButton(
                  onPressed: onSelectServer,
                  style: TextButton.styleFrom(
                      foregroundColor: SagaColors.accentText),
                  child: const Text('Select server'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
