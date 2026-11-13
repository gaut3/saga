part of 'settings_screen.dart';

/// Settings › Data and backup (handoff 13f).
class _DataPage extends ConsumerStatefulWidget {
  const _DataPage();

  @override
  ConsumerState<_DataPage> createState() => _DataPageState();
}

class _DataPageState extends ConsumerState<_DataPage> {
  @override
  Widget build(BuildContext context) {
    ref.watch(sagaThemeVariantProvider);
    return _SettingsPage(
      title: 'Data and backup',
      children: [
          _SettingsTile(
            icon: Icons.upload_outlined,
            title: 'Export progress',
            subtitle: 'Share a backup of your listening positions and bookmarks',
            onTap: _exportProgress,
          ),
          _SettingsTile(
            icon: Icons.download_outlined,
            title: 'Import progress',
            subtitle: 'Restore from an exported backup file',
            onTap: _importProgress,
          ),
          _SettingsTile(
            icon: Icons.delete_sweep_outlined,
            title: 'Clear listening progress',
            subtitle: 'Remove all bookmarks and resume positions',
            iconColor: Colors.orangeAccent,
            onTap: _confirmClearProgress,
          ),
      ],
    );
  }

  Future<void> _exportProgress() async {
    try {
      await ProgressBackup.export();
    } catch (e) {
      AppLog.log('backup', 'export failed: $e');
      // Friendly text only — the raw error can carry a file path.
      if (mounted) {
        showSagaToast(context,
            'Export failed. Details are in the diagnostics log.',
            isError: true);
      }
    }
  }

  Future<void> _importProgress() async {
    try {
      final data = await ProgressBackup.pickAndParse();
      if (data == null || !mounted) return;

      // Warn if the backup came from a different Plex server. Plex ratingKeys
      // are per-server integers — restoring across servers can silently overwrite
      // positions for unrelated books that happen to share the same integer key.
      final backupId = data.serverMachineIdentifier;
      final localId = PlexClient.instance.machineIdentifier;
      if (backupId != null && localId != null && backupId != localId) {
        final proceed = await confirmDialog(
          context,
          title: 'Different server',
          message: 'This backup is from a different Plex server. '
              'Book IDs may overlap, so restoring could overwrite positions '
              'for unrelated books. Continue anyway?',
          confirmLabel: 'Continue',
        );
        if (!proceed || !mounted) return;
      }

      final conflicts = ProgressBackup.detectConflicts(data);
      Set<String>? skipKeys;

      if (conflicts.isEmpty) {
        final confirmed = await confirmDialog(
          context,
          title: 'Restore progress',
          message:
              'Restore ${data.positions.length} listening position${data.positions.length == 1 ? '' : 's'}, '
              '${data.completed.length} completed, '
              '${data.namedBookmarks.length} bookmark${data.namedBookmarks.length == 1 ? '' : 's'}?',
          confirmLabel: 'Restore',
        );
        if (!confirmed) return;
        skipKeys = const {};
      } else {
        skipKeys = await showDialog<Set<String>>(
          context: context,
          builder: (_) => _ConflictResolutionDialog(
            conflicts: conflicts,
            nonConflictCount: data.positions.length - conflicts.length,
          ),
        );
      }

      if (skipKeys == null || !mounted) return;

      await ProgressBackup.restore(data, skipPositionKeys: skipKeys);
      // Restore writes five stores; every surface gated on a revision has to
      // hear about it, or the imported data stays invisible until a restart
      // (collections and history did exactly that).
      ref.read(completionRevisionProvider.notifier).state++;
      ref.read(bookmarkRevisionProvider.notifier).state++;
      ref.read(customCollectionRevisionProvider.notifier).state++;
      ref.read(historyRevisionProvider.notifier).state++;
      // Named bookmarks bypass the notifier on restore — drop its per-book
      // caches so the player's bookmark sheet re-reads the store.
      ref.invalidate(bookmarkNotifierProvider);

      AppLog.log('backup',
          'restored ${data.positions.length} positions '
          '(${conflicts.length} conflicts, ${skipKeys.length} kept local)');
      if (mounted) showSagaToast(context, 'Progress restored');
    } on StateError {
      AppLog.log('backup', 'import failed: file had no readable path or bytes');
      if (mounted) showSagaToast(context, 'Could not read the selected file.', isError: true);
    } catch (e) {
      AppLog.log('backup', 'import failed: $e');
      // Friendly text only — the raw error can carry a file path.
      if (mounted) {
        showSagaToast(context,
            'Import failed. Details are in the diagnostics log.',
            isError: true);
      }
    }
  }

  Future<void> _confirmClearProgress() async {
    final confirmed = await confirmDialog(
      context,
      title: 'Clear progress',
      message: 'This will permanently erase:\n'
          '• All listening positions\n'
          '• Listening history, streaks and heatmap\n'
          '• Completed-book records\n'
          '• Named bookmarks\n'
          '• Session logs\n\n'
          'This cannot be undone.',
      confirmLabel: 'Clear all',
      confirmColor: Colors.orangeAccent,
    );
    if (confirmed) {
      var cleared = false;
      try {
        await BookmarkStore.clearAll();
        await CompletedBooksStore.clearAll();
        await ListeningHistoryStore.clearAll();
        await NamedBookmarkStore.clearAll();
        await PlaybackLogStore.clearAll();
        await ListenDaysStore.clearAll();
        cleared = true;
      } catch (e) {
        AppLog.log('storage', 'clear progress failed partway: $e');
      } finally {
        // Bump even after a partial wipe: whatever did clear must not keep
        // showing until a restart.
        if (mounted) {
          ref.read(bookmarkRevisionProvider.notifier).state++;
          ref.read(completionRevisionProvider.notifier).state++;
          ref.read(historyRevisionProvider.notifier).state++;
        }
      }
      if (!mounted) return;
      showSagaToast(context, cleared
          ? 'Listening progress cleared'
          : "Couldn't clear everything. Try again.");
    }
  }
}

// ── Backup conflict resolution ─────────────────────────────────────────────────

class _ConflictResolutionDialog extends StatefulWidget {
  final List<PositionConflict> conflicts;
  final int nonConflictCount;

  const _ConflictResolutionDialog({
    required this.conflicts,
    required this.nonConflictCount,
  });

  @override
  State<_ConflictResolutionDialog> createState() =>
      _ConflictResolutionDialogState();
}

class _ConflictResolutionDialogState
    extends State<_ConflictResolutionDialog> {
  // Keys whose local position the user wants to keep (not overwritten).
  // Defaults to all conflict keys — "keep current" is the safe default.
  late final Set<String> _keepLocal;

  @override
  void initState() {
    super.initState();
    _keepLocal = widget.conflicts.map((c) => c.bookKey).toSet();
  }

  bool get _allKeep => _keepLocal.length == widget.conflicts.length;
  bool get _allRestore => _keepLocal.isEmpty;

  String _fmtDate(DateTime dt) => '${historyMonthAbbr(dt.month)} ${dt.day}';

  @override
  Widget build(BuildContext context) {
    final n = widget.conflicts.length;
    final showBulk = n > 3;
    return AlertDialog(
      backgroundColor: SagaColors.surface,
      title: Text('Restore progress', style: TextStyle(color: SagaColors.fg)),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$n book${n == 1 ? '' : 's'} '
              'ha${n == 1 ? 's' : 've'} a newer local position than this backup.',
              style: TextStyle(color: SagaColors.fgMuted, fontSize: 13),
            ),
            if (widget.nonConflictCount > 0) ...[
              const SizedBox(height: 4),
              Text(
                '${widget.nonConflictCount} other position'
                '${widget.nonConflictCount == 1 ? '' : 's'} '
                'will be restored automatically.',
                style: TextStyle(color: SagaColors.fgSubtle, fontSize: 12),
              ),
            ],
            if (showBulk) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  _bulkChip('Keep all current', _allKeep,
                      () => setState(() => _keepLocal.addAll(
                          widget.conflicts.map((c) => c.bookKey)))),
                  const SizedBox(width: 8),
                  _bulkChip('Restore all', _allRestore,
                      () => setState(() => _keepLocal.clear())),
                ],
              ),
            ],
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: widget.conflicts.length,
                separatorBuilder: (_, _) => Divider(
                  color: SagaColors.border,
                  height: 1,
                  thickness: 0.5,
                ),
                itemBuilder: (_, i) => _conflictTile(widget.conflicts[i]),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.pop(context, Set<String>.from(_keepLocal)),
          child:
              Text('Restore', style: TextStyle(color: SagaColors.accentText)),
        ),
      ],
    );
  }

  Widget _bulkChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? SagaColors.accent.withValues(alpha: 0.15)
              : SagaColors.surfaceAlt,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? SagaColors.accent
                : SagaColors.fgSubtle.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? SagaColors.accentText : SagaColors.fgMuted,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _conflictTile(PositionConflict c) {
    final keepLocal = _keepLocal.contains(c.bookKey);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Book #${c.bookKey}',
            style: TextStyle(
                color: SagaColors.fg,
                fontSize: 13,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _positionChip(
                  label: 'Keep current',
                  pos: c.local,
                  selected: keepLocal,
                  onTap: () => setState(() => _keepLocal.add(c.bookKey)),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _positionChip(
                  label: 'Restore',
                  pos: c.backup,
                  selected: !keepLocal,
                  onTap: () => setState(() => _keepLocal.remove(c.bookKey)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _positionChip({
    required String label,
    required BookPosition pos,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? SagaColors.accent.withValues(alpha: 0.12)
              : SagaColors.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? SagaColors.accent
                : SagaColors.fgSubtle.withValues(alpha: 0.25),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (selected) ...[
                  Icon(Icons.check_circle, color: SagaColors.accent, size: 11),
                  const SizedBox(width: 3),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color:
                        selected ? SagaColors.accentText : SagaColors.fgSubtle,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              fmtDurationMs(pos.absolutePositionMs),
              style: TextStyle(color: SagaColors.fg, fontSize: 12),
            ),
            Text(
              _fmtDate(pos.savedAt),
              style: TextStyle(color: SagaColors.fgSubtle, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
