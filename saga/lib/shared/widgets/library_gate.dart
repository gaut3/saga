import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/saga_theme.dart';
import 'offline_note.dart';

/// The library tabs' shared gate: the tab's real content when the library
/// resolves, an honest offline body when it can't.
///
/// Mirrors Home's rule: the offline signal is the library key failing to
/// *resolve* — an actual failed fetch — never a connectivity guess (the note
/// above `connectivityProvider` in core/providers.dart is the standing ban on
/// guessing, and why: idle VPNs, captive portals and WAN-less routers all
/// report a healthy network). While the key is still being asked for, the
/// offline body shows its content without the unreachable note, so nothing
/// claims to be broken a second before it turns out not to be. Recovery is
/// automatic — `activeLibraryKeyProvider` re-runs when the radios return.
///
/// Before this gate the three tabs answered the same situation with a
/// spinner, then a bare error view or "No library found" — screens that
/// looked broken on a plane while Home, one tab over, worked.
class LibraryGate extends ConsumerWidget {
  /// Title for the offline body's app bar (the online content brings its own).
  final String title;

  final Widget Function(String libraryKey) online;

  /// Shown by the [OfflineNote]; defaults to Home's wording, which fits tabs
  /// that show local content. Tabs with nothing to show say what's missing.
  final String? offlineMessage;

  /// Local-data slivers for the offline body (e.g. Browse's downloaded
  /// grid), reading the same local stores Home's shelves do. Omit for tabs
  /// whose content genuinely needs the server.
  final List<Widget> Function(BuildContext context)? offlineSlivers;

  const LibraryGate({
    super.key,
    required this.title,
    required this.online,
    this.offlineMessage,
    this.offlineSlivers,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(sagaThemeVariantProvider);
    final libraryKeyAsync = ref.watch(activeLibraryKeyProvider);
    // valueOrNull deliberately treats an error like an unresolved key: a
    // server that failed outright leaves local content usable, so a failure
    // demotes the tab to its offline self rather than a raw error screen —
    // the same choice Home makes.
    final key = libraryKeyAsync.valueOrNull;
    if (key != null) return online(key);

    // Only the FIRST-ever resolution counts as "still being asked": every
    // connectivity flip re-runs the provider, and plain isLoading flashed the
    // spinner over an already-settled offline body on each re-check. A reload
    // carries its previous answer (hasValue), so it keeps the note and
    // content on screen until a real answer replaces them.
    final resolving = libraryKeyAsync.isLoading && !libraryKeyAsync.hasValue;
    final content = offlineSlivers?.call(context) ?? const <Widget>[];

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          backgroundColor: Colors.transparent,
          foregroundColor: SagaColors.fg,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          flexibleSpace: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [SagaColors.bg, SagaColors.bg.withValues(alpha: 0.0)],
                stops: const [0.6, 1.0],
              ),
            ),
          ),
          title: Text(title,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
        ),
        if (!resolving)
          SliverToBoxAdapter(child: OfflineNote(message: offlineMessage)),
        ...content,
        if (resolving && content.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
                child: CircularProgressIndicator(color: SagaColors.accent)),
          ),
      ],
    );
  }
}
