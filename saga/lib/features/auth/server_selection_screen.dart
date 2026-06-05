import 'package:flutter/material.dart';
import '../../core/theme/saga_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/widgets/saga_toast.dart';

import '../../core/providers.dart';

class ServerSelectionScreen extends ConsumerWidget {
  final bool isSetup;
  const ServerSelectionScreen({super.key, this.isSetup = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serversAsync = ref.watch(serverListProvider);

    return Scaffold(
      backgroundColor: SagaColors.bg,
      appBar: AppBar(
        title: Text(isSetup ? 'Connect to Plex' : 'Select Server'),
        backgroundColor: SagaColors.surface,
        foregroundColor: SagaColors.fg,
        automaticallyImplyLeading: !isSetup,
      ),
      body: serversAsync.when(
        loading: () => Center(
          child: CircularProgressIndicator(color: SagaColors.accent),
        ),
        error: (_, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
              const SizedBox(height: 12),
              Text('Failed to load servers — check your connection',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: SagaColors.fgMuted)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.invalidate(serverListProvider),
                style: ElevatedButton.styleFrom(
                    backgroundColor: SagaColors.accent),
                child: Text('Retry',
                    style: TextStyle(color: SagaColors.accentFg)),
              ),
            ],
          ),
        ),
        data: (servers) {
          if (servers.isEmpty) {
            return Center(
              child: Text(
                'No Plex servers found.\nMake sure Plex Media Server is running.',
                textAlign: TextAlign.center,
                style: TextStyle(color: SagaColors.fgMuted),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: servers.length + (isSetup ? 1 : 0),
            itemBuilder: (context, index) {
              if (isSetup && index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Choose your server',
                          style: TextStyle(
                              color: SagaColors.fg,
                              fontSize: 18,
                              fontWeight: FontWeight.bold)),
                      SizedBox(height: 6),
                      Text('Select the Plex server that has your audiobooks.',
                          style: TextStyle(color: SagaColors.fgMuted, fontSize: 14)),
                    ],
                  ),
                );
              }
              final server = servers[isSetup ? index - 1 : index];
              return Card(
                color: SagaColors.surface,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  leading: Icon(Icons.dns, color: SagaColors.accent),
                  title: Text(
                    server.name,
                    style: TextStyle(color: SagaColors.fg),
                  ),
                  subtitle: Text(
                    '${server.connections.length} ${server.connections.length == 1 ? 'connection' : 'connections'}',
                    style: TextStyle(color: SagaColors.fgMuted),
                  ),
                  trailing: Icon(Icons.chevron_right, color: SagaColors.fgMuted),
                  onTap: () => _selectServer(context, ref, server),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _selectServer(
      BuildContext context, WidgetRef ref, dynamic server) async {
    final discovery = ref.read(plexServerDiscoveryProvider);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: CircularProgressIndicator(color: SagaColors.accent),
      ),
    );

    await discovery.selectServer(server);

    if (!context.mounted) return;

    ref.read(activeServerUriProvider.notifier).state =
        ref.read(plexClientProvider).serverUri;
    Navigator.of(context).pop(); // close loading dialog
    if (!isSetup) Navigator.of(context).pop(); // back to settings (not needed in setup)

    if (ref.read(plexClientProvider).serverUri == null) {
      if (context.mounted) {
        showSagaToast(context, 'Could not reach server. Check your connection.',
            duration: const Duration(seconds: 4));
      }
    }
  }
}
