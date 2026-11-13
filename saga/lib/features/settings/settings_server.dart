part of 'settings_screen.dart';

/// Settings › Server: today's Server section. Becomes 13d Sources with
/// Audiobookshelf (1.6.0).
class _ServerPage extends ConsumerStatefulWidget {
  const _ServerPage();

  @override
  ConsumerState<_ServerPage> createState() => _ServerPageState();
}

class _ServerPageState extends ConsumerState<_ServerPage> {
  late bool _redactServer = SettingsStore.redactServerAddress;

  @override
  Widget build(BuildContext context) {
    ref.watch(sagaThemeVariantProvider);
    final client = ref.watch(plexClientProvider);
    return _SettingsPage(
      title: 'Server',
      children: [
          _SettingsTile(
            icon: Icons.dns_outlined,
            title: 'Plex server',
            subtitle: client.serverUri == null
                ? 'Not connected'
                : _redactServer
                    ? maskAddress(client.serverUri!)
                    : client.serverUri!,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const ServerSelectionScreen()),
            ).then((_) => ref.invalidate(activeLibraryKeyProvider)),
          ),
          _SwitchTile(
            icon: Icons.visibility_off_outlined,
            title: 'Redact server address',
            subtitle: 'Hide IP in screenshots and recordings',
            value: _redactServer,
            onChanged: (v) async {
              await SettingsStore.setRedactServerAddress(v);
              if (!mounted) return;
              setState(() => _redactServer = v);
            },
          ),
          _LibraryPickerTile(),
      ],
    );
  }
}


class _LibraryPickerTile extends ConsumerWidget {
  const _LibraryPickerTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final librariesAsync = ref.watch(librariesProvider);
    final selectedKey = ref.watch(selectedLibraryKeyProvider);

    final subtitle = librariesAsync.when(
      loading: () => 'Loading…',
      error: (_, _) => 'Could not load libraries',
      data: (libs) {
        if (libs.isEmpty) return 'No libraries found';
        if (selectedKey == null) return libs.first.title;
        return libs
                .firstWhere((l) => l.key == selectedKey,
                    orElse: () => libs.first)
                .title;
      },
    );

    return _SettingsTile(
      icon: Icons.library_books_outlined,
      title: 'Active library',
      subtitle: subtitle,
      onTap: () => _showPicker(context, ref,
          librariesAsync.valueOrNull ?? [], selectedKey),
    );
  }

  void _showPicker(BuildContext context, WidgetRef ref,
      List<PlexLibrary> libraries, String? selectedKey) {
    if (libraries.isEmpty) return;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    showSagaSheet<void>(context, (_) => Padding(
        padding: EdgeInsets.fromLTRB(0, 4, 0, 24 + bottomPad),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SagaSheetTitle('Select library',
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12)),
            ...libraries.map((lib) {
              final isSelected = selectedKey == lib.key ||
                  (selectedKey == null && lib == libraries.first);
              return ListTile(
                leading: Icon(
                  Icons.library_music_outlined,
                  color: isSelected ? SagaColors.accent : SagaColors.fgMuted,
                ),
                title: Text(lib.title,
                    style: TextStyle(
                        color:
                            isSelected ? SagaColors.accentText : SagaColors.fg,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal)),
                trailing: isSelected
                    ? Icon(Icons.check, color: SagaColors.accent)
                    : null,
                onTap: () async {
                  await SettingsStore.setSelectedLibraryKey(lib.key);
                  if (!context.mounted) return;
                  ref.read(selectedLibraryKeyProvider.notifier).state =
                      lib.key;
                  ref.invalidate(activeLibraryKeyProvider);
                  Navigator.pop(context);
                },
              );
            }),
          ],
        ),
      ), scrollable: false);
  }
}
