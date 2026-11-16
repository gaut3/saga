part of 'settings_screen.dart';

/// Settings › About (handoff 13g), with the brand footer at its foot.
class _AboutPage extends ConsumerStatefulWidget {
  /// Opened by the update banner: scroll to "Check for updates".
  final bool revealUpdate;
  const _AboutPage({this.revealUpdate = false});

  @override
  ConsumerState<_AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends ConsumerState<_AboutPage> {
  late bool _updateCheck = SettingsStore.updateCheckEnabled;
  final _updateRowKey = GlobalKey();
  // From the code, not the platform: iOS reports it without its "-dev".
  static const _version = 'v$appVersionName';
  int _versionTaps = 0;

  void _onVersionTap() {
    if (!BuildChannel.isPrerelease) return;
    if (SettingsStore.developerOptions) {
      showSagaToast(context, 'Developer options are already on');
      return;
    }
    final left = 7 - ++_versionTaps;
    if (left <= 0) {
      _versionTaps = 0;
      SettingsStore.setDeveloperOptions(true);
      showSagaToast(context, 'Developer options are on, under About in Settings');
    } else if (left <= 3) {
      showSagaToast(context,
          left == 1 ? 'One more tap' : '$left taps from developer options');
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.revealUpdate) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final row = _updateRowKey.currentContext;
        if (row == null || !row.mounted) return;
        Scrollable.ensureVisible(row,
            alignment: 0.5, duration: const Duration(milliseconds: 300));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(sagaThemeVariantProvider);
    return _SettingsPage(
      title: 'About',
      children: [
          _SettingsTile(
            icon: Icons.lock_outline,
            title: 'Privacy',
            subtitle: 'Local-first · your server and plex.tv only',
            onTap: () =>
                _showInfoSheet(context, 'Privacy', _privacyText),
          ),
          _SettingsTile(
            icon: Icons.description_outlined,
            title: 'Terms',
            subtitle: 'Unofficial Plex client · provided as-is',
            onTap: () => _showInfoSheet(context, 'Terms', _termsText),
          ),
          _SettingsTile(
            icon: Icons.favorite_outline,
            title: 'Acknowledgements',
            subtitle: 'Open-source licenses & thanks',
            onTap: () => _showAcknowledgements(context),
          ),
          _SwitchTile(
            icon: Icons.update_outlined,
            title: 'Check for updates automatically',
            subtitle:
                'Off by default — one request to GitHub when Saga starts, '
                'and daily if it stays open',
            value: _updateCheck,
            onChanged: (v) async {
              await SettingsStore.setUpdateCheckEnabled(v);
              if (!mounted) return;
              setState(() => _updateCheck = v);
              // Re-run (or clear) the cached result immediately.
              ref.invalidate(updateCheckProvider);
            },
          ),
          Builder(builder: (context) {
            final update = ref.watch(updateCheckProvider).valueOrNull;
            final hasUpdate = update?.isNewer == true;
            // Say which of the four things happened. "Up to date" and
            // "couldn't check" used to read identically, so a check that
            // had never worked looked exactly like one that had run and
            // found nothing — and anyone running a build newer than the
            // latest release only ever sees the quiet outcomes.
            final subtitle = switch (update?.status) {
              UpdateCheckStatus.available =>
                'Update available: ${update!.latestTag}',
              UpdateCheckStatus.current =>
                'Up to date (${update!.currentVersion})',
              UpdateCheckStatus.failed =>
                "Couldn't reach GitHub — tap to check yourself",
              _ => 'View releases on GitHub',
            };
            return _SettingsTile(
              key: _updateRowKey,
              icon: hasUpdate
                  ? Icons.new_releases_outlined
                  : Icons.system_update_outlined,
              title: 'Check for updates',
              subtitle: subtitle,
              onTap: () => launchUrl(
                Uri.parse('https://github.com/gaut3/saga/releases'),
                mode: LaunchMode.externalApplication,
              ),
            );
          }),
          _SettingsTile(
            icon: Icons.bug_report_outlined,
            title: 'Copy diagnostics',
            subtitle: 'Recent errors, redacted — for bug reports',
            onTap: () async {
              await HomeWidgetSync.takeNativeLog();
              if (!mounted) return;
              final dump = AppLog.dump();
              if (dump.isEmpty) {
                showSagaToast(this.context, 'No diagnostics recorded yet');
                return;
              }
              await Clipboard.setData(ClipboardData(text: dump));
              if (!mounted) return;
              showSagaToast(this.context,
                  'Diagnostics copied — server address and token are redacted');
            },
          ),
          // Sits directly under "Copy diagnostics" because that is the
          // order the two are used in: copy, then paste into the report.
          _SettingsTile(
            icon: Icons.open_in_new,
            title: 'Report an issue',
            subtitle: 'Opens GitHub — paste the diagnostics there',
            onTap: () => launchUrl(
              Uri.parse('https://github.com/gaut3/saga/issues/new'),
              mode: LaunchMode.externalApplication,
            ),
          ),
        const SizedBox(height: 36),

        // Brand footer — the actual app/launcher icon + wordmark.
          // Brand footer — the actual app/launcher icon + wordmark.
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: Image.asset(
                    'assets/icons/ic_launcher.png',
                    width: 62,
                    height: 62,
                    cacheWidth: 124,
                  ),
                ),
                const SizedBox(height: 12),
                const SagaWordmark(fontSize: 22),
                const SizedBox(height: 6),
                // Seven taps unlock developer options on a beta or dev
                // build, as the build number does in Android's settings.
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _onVersionTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 6),
                    child: Text(_version,
                        style: TextStyle(
                            color: SagaColors.fgSubtle, fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  void _showInfoSheet(BuildContext context, String title, String body) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    showSagaSheet(context, (ctx) => Padding(
        padding: EdgeInsets.only(bottom: bottomPad),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SagaSheetTitle(title,
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 10)),
            ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.7),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Text(body,
                    style: TextStyle(
                        color: SagaColors.fgMuted, fontSize: 14, height: 1.55)),
              ),
            ),
          ],
        ),
      ));
  }

  void _showAcknowledgements(BuildContext context) {
    const credits = <(String, String)>[
      ('just_audio', 'audio playback engine'),
      ('audio_service', 'background playback & media notification'),
      ('audio_session', 'audio focus & interruptions'),
      ('flutter_riverpod', 'state management'),
      ('hive', 'encrypted on-device storage'),
      ('dio', 'networking'),
      ('cached_network_image', 'cover-art caching'),
      ('connectivity_plus', 'network status'),
      ('flutter_secure_storage', 'key storage'),
      // Not open source, and the only Google component in the app. Named
      // because a privacy screen that lists only the flattering dependencies
      // isn't worth reading.
      ('Google Cast SDK', 'Chromecast support (Google, not open source)'),
    ];
    final bottomPad = MediaQuery.of(context).padding.bottom;
    showSagaSheet(context, (ctx) => Padding(
        padding: EdgeInsets.only(bottom: bottomPad),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SagaSheetTitle('Acknowledgements',
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 4)),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                  'Saga stands on a lot of open-source work — thank you to the '
                  'maintainers of, among others:',
                  style: TextStyle(
                      color: SagaColors.fgMuted, fontSize: 13.5, height: 1.5)),
            ),
            ...credits.map((c) => Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(c.$1,
                          style: TextStyle(
                              color: SagaColors.fg,
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(c.$2,
                            style: TextStyle(
                                color: SagaColors.fgSubtle, fontSize: 12)),
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  showLicensePage(
                    context: context,
                    applicationName: 'Saga',
                    applicationVersion: _version.isEmpty ? null : _version,
                    applicationIcon: const Padding(
                      padding: EdgeInsets.all(12),
                      child: SagaMark(size: 56),
                    ),
                  );
                },
                child: Text('View all licenses',
                    style: TextStyle(color: SagaColors.accentText)),
              ),
            ),
          ],
        ),
      ));
  }

  // Kept deliberately honest rather than flattering: every line here is
  // checkable, and the last one describes something Saga cannot prevent. A
  // privacy screen that only lists the good parts is the kind of claim this
  // app exists not to make.
  static const _privacyText =
      'Saga is local-first and built to keep your data yours.\n\n'
      '• Your positions, bookmarks, listening history and settings live only on '
      'this device, encrypted at rest. Downloaded audio files live in Saga\'s '
      'private storage, unreadable to other apps, though the audio itself is '
      'not encrypted — a player has to be able to read it.\n\n'
      '• The only servers Saga talks to are your own Plex server (to browse and '
      'stream your library) and plex.tv (to sign in). If you switch on the update '
      'check in About, that adds one request to GitHub when Saga starts, and '
      'once a day if it stays open, and nothing else — it is off unless you '
      'turn it on.\n\n'
      '• No analytics, no tracking, no advertising, no telemetry. Nothing about '
      'you or your library is sent to the author or to anyone else, ever.\n\n'
      '• Saga requests no microphone, camera, contacts, or location access. Even the '
      'now-playing visualizer reads the audio in-process — never the microphone.\n\n'
      '• Casting is the one place a key to your server travels in a web address '
      'rather than a protected header, because a Chromecast fetches the audio '
      'itself and cannot send headers — and what a Chromecast is playing is '
      'readable by other devices on your Wi-Fi. Saga asks your server for a '
      'temporary, single-server pass for this, and only falls back to your '
      'account key if the server cannot issue one. A known flaw in Plex Media '
      'Server lets such a pass be traded for a permanent key, so on an '
      'affected server it protects less than it was meant to. The privacy '
      'policy has the full picture.\n\n'
      '• To work in a car and on the lock screen, Saga has to tell Android what '
      'you are listening to, and Android lets other installed apps read that: the '
      'books you are part-way through, your downloads and collections, and what is '
      'playing now. No password or server address is ever exposed this way, but the '
      'titles are visible. Every audiobook and music app that offers these features '
      'is in the same position.\n\n'
      '• If you add Saga\'s home-screen widget, it shows your current book\'s title, '
      'chapter, cover and progress on the home screen, where anyone holding the '
      'phone can see them. To draw it, Saga keeps a copy of those details '
      'unencrypted in its private storage. Signing out removes the book from it.';

  static const _termsText =
      'Saga is an independent, unofficial client for Plex Media Server. It is not '
      'affiliated with, endorsed by, or sponsored by Plex, Inc.\n\n'
      'Saga is provided as-is, without warranty of any kind. You are responsible for '
      'your own Plex server, account, and content, and for complying with the terms '
      'of any service you connect to.\n\n'
      '“Plex” is a trademark of Plex, Inc., used here only to describe compatibility.';
}
