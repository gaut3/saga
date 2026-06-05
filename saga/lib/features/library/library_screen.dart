import 'package:flutter/material.dart';
import '../../core/theme/saga_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../shared/widgets/mini_player_bar.dart';
import '../auth/server_selection_screen.dart';
import 'books_screen.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final librariesAsync = ref.watch(librariesProvider);
    final serverUri = ref.watch(activeServerUriProvider);

    return Scaffold(
      backgroundColor: SagaColors.bg,
      bottomNavigationBar: const MiniPlayerBar(),
      appBar: AppBar(
        title: const Text('Libraries'),
        backgroundColor: SagaColors.surface,
        foregroundColor: SagaColors.fg,
        actions: [
          IconButton(
            icon: const Icon(Icons.dns_outlined),
            tooltip: 'Switch server',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const ServerSelectionScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () => _confirmSignOut(context, ref),
          ),
        ],
      ),
      body: serverUri == null
          ? _noServerView(context)
          : librariesAsync.when(
              loading: () => Center(
                child: CircularProgressIndicator(color: SagaColors.accent),
              ),
              error: (e, _) => _errorView(context, ref, e),
              data: (libraries) {
                if (libraries.isEmpty) {
                  return Center(
                    child: Text(
                      'No music libraries found.\nMake sure you have a Music library in Plex.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: SagaColors.fgMuted),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: libraries.length,
                  itemBuilder: (context, index) {
                    final lib = libraries[index];
                    return Card(
                      color: SagaColors.surface,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        leading:
                            Icon(Icons.library_music, color: SagaColors.accent),
                        title: Text(lib.title,
                            style: TextStyle(color: SagaColors.fg)),
                        trailing: Icon(Icons.chevron_right,
                            color: SagaColors.fgMuted),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => BooksScreen(library: lib),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }

  Widget _noServerView(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.dns_outlined, size: 64, color: Colors.white30),
          const SizedBox(height: 16),
          Text(
            'No server selected.',
            style: TextStyle(color: SagaColors.fgMuted, fontSize: 16),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ServerSelectionScreen()),
            ),
            style: ElevatedButton.styleFrom(
                backgroundColor: SagaColors.accent),
            child:
                Text('Select Server', style: TextStyle(color: SagaColors.accentFg)),
          ),
        ],
      ),
    );
  }

  Widget _errorView(BuildContext context, WidgetRef ref, Object error) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
          const SizedBox(height: 12),
          Text('$error',
              textAlign: TextAlign.center,
              style: TextStyle(color: SagaColors.fgMuted)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => ref.invalidate(librariesProvider),
            style: ElevatedButton.styleFrom(
                backgroundColor: SagaColors.accent),
            child: Text('Retry', style: TextStyle(color: SagaColors.accentFg)),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: SagaColors.surface,
        title: Text('Sign out', style: TextStyle(color: SagaColors.fg)),
        content: Text('Sign out of your Plex account?',
            style: TextStyle(color: SagaColors.fgMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(plexClientProvider).clearAuth();
      ref.read(isAuthenticatedProvider.notifier).state = false;
    }
  }
}
