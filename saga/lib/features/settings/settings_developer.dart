part of 'settings_screen.dart';

/// Settings › Developer options: tools for testing Saga, on beta and dev
/// builds only (sync design § Developer options). Unlocked from About.
///
/// Rules for everything on this page: nothing here writes a position
/// directly, and nothing shows a token or an unredacted address — a
/// screenshot of it can end up in a bug report.
class _DeveloperPage extends ConsumerStatefulWidget {
  const _DeveloperPage();

  @override
  ConsumerState<_DeveloperPage> createState() => _DeveloperPageState();
}

class _DeveloperPageState extends ConsumerState<_DeveloperPage> {
  List<SaveAuditEntry> _saves = SaveAuditStore.entries();
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // The live position and the newest saves, once a second.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _saves = SaveAuditStore.entries());
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  static String _clock(DateTime t) =>
      '${fmtTime(t)}:${t.second.toString().padLeft(2, '0')}';

  static final _mono = TextStyle(
      color: SagaColors.fg,
      fontSize: 14,
      fontFeatures: const [FontFeature.tabularFigures()]);

  @override
  Widget build(BuildContext context) {
    ref.watch(sagaThemeVariantProvider);
    final subtle = TextStyle(color: SagaColors.fgSubtle, fontSize: 12);
    return _SettingsPage(
      title: 'Developer options',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(
              'For testing Saga. Only beta and dev builds have this page; a '
              'release never shows or reads it.',
              style: TextStyle(color: SagaColors.fgMuted, fontSize: 13)),
        ),
        _SectionHeader('Now'),
        _now(subtle),
        const SizedBox(height: 16),
        _SectionHeader('Position saves'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
              'The last ${SaveAuditStore.maxEntries}, newest first, with 10 s '
              'ticks folded into runs. Held: the report waited for playback '
              'to pass the loaded place. Repeat: it said nothing new, so it '
              'wasn\'t sent.',
              style: subtle),
        ),
        if (_saves.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
                'No saves recorded yet. They are recorded while developer '
                'options are on.',
                style: subtle),
          )
        else
          Material(
            color: SagaColors.surface,
            child: Column(
              children: [for (final s in _saves) _saveRow(s, subtle)],
            ),
          ),
        const SizedBox(height: 16),
        _SectionHeader('Timeline queue'),
        ..._queue(subtle),
        const SizedBox(height: 16),
        _SectionHeader('Sync log'),
        _syncLog(subtle),
        const SizedBox(height: 24),
        _SettingsTile(
          icon: Icons.visibility_off_outlined,
          title: 'Hide developer options',
          subtitle: 'Tap the version in About seven times to bring them back',
          onTap: () async {
            await SettingsStore.setDeveloperOptions(false);
            if (!mounted) return;
            Navigator.of(this.context).pop();
          },
        ),
      ],
    );
  }

  /// Reports that couldn't reach Plex, waiting to be replayed (one per book,
  /// the newest). Before a replay Saga reads the book from Plex and drops
  /// the entry if Plex has heard of it since (sync design rule 6).
  List<Widget> _queue(TextStyle subtle) {
    final pending = TimelineQueueStore.all().entries.toList()
      ..sort((a, b) => a.value.savedAt.compareTo(b.value.savedAt));
    final now = DateTime.now();
    String age(DateTime t) {
      final d = now.difference(t);
      if (d.inHours > 0) return '${d.inHours} h ${d.inMinutes % 60} min ago';
      if (d.inMinutes > 0) return '${d.inMinutes} min ago';
      return '${d.inSeconds} s ago';
    }

    return [
      Material(
        color: SagaColors.surface,
        child: Column(
          children: [
            ListTile(
              leading: Icon(
                  pending.isEmpty
                      ? Icons.cloud_done_outlined
                      : Icons.cloud_upload_outlined,
                  color: SagaColors.accent),
              title: Text(
                  pending.isEmpty
                      ? 'Nothing waiting'
                      : '${pending.length} waiting · oldest '
                          '${age(pending.first.value.savedAt)}',
                  style: TextStyle(color: SagaColors.fg)),
              subtitle: Text(
                  'Reports that couldn\'t reach Plex. Each is checked against '
                  'Plex before it\'s sent: if Plex has heard of the book since, '
                  'it\'s dropped.',
                  style: subtle),
            ),
            for (final e in pending)
              ListTile(
                dense: true,
                leading: const SizedBox(width: 24),
                title: Text(
                    '${_clock(e.value.savedAt)}  ·  '
                    '${fmtDuration(Duration(milliseconds: e.value.positionMs))} '
                    'in its file',
                    style: _mono),
                subtitle: Text(
                    '${e.value.state} · book ${e.key} · ${age(e.value.savedAt)}',
                    style: subtle),
              ),
          ],
        ),
      ),
      _SettingsTile(
        icon: Icons.sync_rounded,
        title: 'Sync now',
        subtitle: 'Check and send what is waiting, as coming back online does',
        onTap: () {
          ref.read(playerServiceProvider).flushTimelineQueue();
          showSagaToast(context, 'Sending what is waiting');
        },
      ),
      _SwitchTile(
        icon: Icons.cloud_off_outlined,
        title: 'Simulate offline',
        subtitle: 'Plex calls fail as if the server were down, until Saga '
            'restarts. Audio already loaded keeps playing.',
        value: PlexClient.simulateOffline,
        onChanged: (v) {
          setState(() => PlexClient.simulateOffline = v);
          AppLog.log('dev', 'simulate offline ${v ? 'on' : 'off'}');
        },
      ),
    ];
  }

  /// The newest `[sync]` lines from the diagnostics log: when reports were
  /// held and opened, and what the queue check did with each entry.
  Widget _syncLog(TextStyle subtle) {
    final lines = AppLog.recent('sync');
    return Material(
      color: SagaColors.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: lines.isEmpty
            ? Text('Nothing yet.', style: subtle)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final l in lines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      // "2026-11-13T10:47:29.123 [sync] …" → "10:47:29 …"
                      child: Text(
                          l.length > 30 && l[10] == 'T'
                              ? '${l.substring(11, 19)}  '
                                  '${l.substring(l.indexOf('] ') + 2)}'
                              : l,
                          style: subtle.copyWith(
                              color: SagaColors.fgMuted,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ])),
                    ),
                ],
              ),
      ),
    );
  }

  /// The loaded book: how far the live position is from the last save (what
  /// a kill right now would cost), and whether reports go to Plex.
  Widget _now(TextStyle subtle) {
    final player = ref.read(playerServiceProvider);
    final book = player.currentBookRatingKey;
    final lines = <String>[];
    String title;
    if (book == null) {
      title = 'No book loaded';
    } else {
      title = player.currentTrackInfo?.bookTitle ?? 'Book $book';
      final live = player.absolutePositionMs;
      final saved = BookmarkStore.load(book);
      if (saved == null) {
        lines.add('Now ${fmtBookPositionMs(live)} · not saved yet');
      } else {
        final ago = DateTime.now().difference(saved.savedAt).inSeconds;
        final gapS = ((live - saved.absolutePositionMs) / 1000).round();
        lines.add('Now ${fmtBookPositionMs(live)} · saved '
            '${fmtBookPositionMs(saved.absolutePositionMs)}, ${ago}s ago '
            '(${gapS >= 0 ? '+' : ''}${gapS}s)');
      }
      final held = player.reportHeldUntilMs;
      final last = player.lastReport;
      lines.add(held != null
          ? 'Reports to Plex held until ${fmtBookPositionMs(held)}'
          : 'Reports to Plex go out');
      if (last != null) {
        lines.add('Last sent: ${last.state} at '
            '${fmtDuration(Duration(milliseconds: last.positionMs))} in its '
            'file · book ${last.bookKey}');
      }
    }
    return Material(
      color: SagaColors.surface,
      child: ListTile(
        leading: Icon(
            book == null ? Icons.stop_circle_outlined : Icons.my_location_outlined,
            color: SagaColors.accent),
        title: Text(title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: SagaColors.fg)),
        subtitle: lines.isEmpty
            ? null
            : Text(lines.join('\n'),
                style: subtle.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()])),
      ),
    );
  }

  Widget _saveRow(SaveAuditEntry s, TextStyle subtle) {
    final run = s.count > 1;
    final first = DateTime.fromMillisecondsSinceEpoch(s.id);
    final title = run
        ? '${_clock(first)}–${_clock(s.at)}  ·  '
            '${fmtBookPositionMs(s.fromPositionMs)} → '
            '${fmtBookPositionMs(s.positionMs)}'
        : '${_clock(s.at)}  ·  ${fmtBookPositionMs(s.positionMs)}';

    final refused = s.outcomes.keys.any((k) => k.startsWith('http'));
    final queued = s.outcomes.containsKey('queued');
    final (IconData icon, Color color) = switch (s.report) {
      ReportStatus.held => (Icons.cloud_off_outlined, SagaColors.fgSubtle),
      ReportStatus.repeat => (Icons.repeat_rounded, SagaColors.fgSubtle),
      ReportStatus.sent when refused => (Icons.error_outline, Colors.orangeAccent),
      ReportStatus.sent when queued => (Icons.cloud_upload_outlined, SagaColors.fgSubtle),
      ReportStatus.sent => (Icons.cloud_done_outlined, SagaColors.accent),
    };

    return ListTile(
      dense: true,
      leading: Icon(icon, color: color),
      title: Text(title, style: _mono),
      subtitle: Text(
          '${s.trigger}${run ? ' ×${s.count}' : ''} · book ${s.bookKey} · '
          '${_reportText(s)}',
          style: subtle),
    );
  }

  static String _reportText(SaveAuditEntry s) {
    switch (s.report) {
      case ReportStatus.held:
        return s.heldUntilMs == null
            ? 'held'
            : 'held until ${fmtBookPositionMs(s.heldUntilMs!)}';
      case ReportStatus.repeat:
        return s.count > 1 ? 'repeats, not sent' : 'repeat, not sent';
      case ReportStatus.sent:
        final landed = s.outcomes.values.fold<int>(0, (a, b) => a + b);
        final pending = s.count - landed;
        if (s.count == 1) {
          final o = s.outcomes.keys.firstOrNull;
          return switch (o) {
            null => 'sending…',
            'ok' => 'sent to Plex',
            'queued' => 'no answer, queued',
            _ => 'Plex refused it ($o)',
          };
        }
        return [
          'sent ×${s.count}',
          for (final e in s.outcomes.entries) '${e.value} ${e.key}',
          if (pending > 0) '$pending sending',
        ].join(' · ');
    }
  }
}
