import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/cast/cast_service.dart';
import '../../core/plex/plex_client.dart';
import '../../core/theme/saga_theme.dart';
import '../../shared/widgets/saga_mark.dart' show AnimatedSagaMark, SagaMarkState;
import '../../shared/widgets/saga_sheet.dart';
import '../../shared/widgets/saga_toast.dart';
import 'player_service.dart';

void showCastSheet(BuildContext context,
    {required AudioPlayerService service}) {
  showSagaSheet<void>(context, (_) => _CastSheet(service: service),
      scrollable: false);
}

// ── Cast sheet ────────────────────────────────────────────────────────────────

class _CastSheet extends ConsumerStatefulWidget {
  final AudioPlayerService service;
  const _CastSheet({required this.service});

  @override
  ConsumerState<_CastSheet> createState() => _CastSheetState();
}

class _CastSheetState extends ConsumerState<_CastSheet> {
  late final CastService _cast;
  StreamSubscription<CastState>? _stateSub;
  StreamSubscription<String>? _errorSub;
  // Set when the user picks a device; the media handoff fires once the
  // session reports connected.
  bool _pendingLoad = false;

  @override
  void initState() {
    super.initState();
    _cast = ref.read(castServiceProvider);
    _cast.startDiscovery();
    _stateSub = _cast.stateStream.listen((s) {
      if (s == CastState.connected && _pendingLoad) {
        _pendingLoad = false;
        _castCurrentTrack();
      }
    });
    // Surface session failures — without this the sheet silently snaps back
    // to the device list with no explanation of what went wrong.
    _errorSub = _cast.errorStream.listen((reason) {
      _pendingLoad = false;
      if (mounted) {
        showSagaToast(context, 'Cast connection failed: $reason',
            isError: true);
      }
    });
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _errorSub?.cancel();
    _cast.stopDiscovery(); // active scanning costs battery — only while open
    super.dispose();
  }

  /// Hands the current track to the Cast device: pauses local playback, then
  /// loads the server stream URL at the current position with the correct MIME
  /// type. The device can't send headers and can't reach a downloaded file on
  /// the phone, so the credential travels in the URL — [PlexClient.buildCastMedia]
  /// decides which credential that is and whether artwork comes with it.
  Future<void> _castCurrentTrack() async {
    final service = widget.service;
    final track = service.currentTrackInfo;
    if (track == null) return;
    final media = await PlexClient.instance.buildCastMedia(
      partKey: track.partKey,
      thumbPath: track.thumbPath,
    );
    if (media == null) {
      if (mounted) {
        showSagaToast(context, 'Casting needs your Plex server to be reachable.',
            isError: true);
      }
      return;
    }
    final positionMs = service.player.position.inMilliseconds;
    await service.pause();
    await _cast.loadMedia(
      url: media.streamUrl,
      title: track.bookTitle ?? track.title,
      artist: track.authorName ?? '',
      artwork: media.artUrl ?? '',
      contentType: castContentTypeFor(track.partFile),
      positionMs: positionMs,
    );
  }

  /// Pulls the playback position back from the Cast device, ends the session,
  /// and seeks the (paused) local player there so resuming continues
  /// seamlessly from where the cast left off.
  Future<void> _disconnect() async {
    final posMs = await _cast.getCastPosition();
    await _cast.stopCasting();
    if (posMs > 0) {
      await widget.service.player.seek(Duration(milliseconds: posMs));
      await widget.service.savePosition();
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SagaSheetTitle('Cast to device',
              padding: const EdgeInsets.fromLTRB(0, 4, 0, 16)),
          StreamBuilder<CastState>(
            stream: _cast.stateStream,
            initialData: _cast.state,
            builder: (context, snap) {
              final state = snap.data ?? CastState.idle;

              if (state == CastState.connected) {
                return Column(
                  children: [
                    ListTile(
                      leading:
                          Icon(Icons.cast_connected, color: SagaColors.accent),
                      title: Text('Casting audio',
                          style: TextStyle(color: SagaColors.fg)),
                      subtitle: Text('Audio is playing on the Cast device',
                          style: TextStyle(
                              color: SagaColors.fgSubtle, fontSize: 12)),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _disconnect,
                        icon: const Icon(Icons.cast_outlined),
                        label: const Text('Disconnect'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: const BorderSide(color: Colors.redAccent),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                );
              }

              if (state == CastState.connecting) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                      child: AnimatedSagaMark(
                          size: 36, state: SagaMarkState.buffering)),
                );
              }

              // Idle: live device list from active discovery.
              return StreamBuilder<List<CastDevice>>(
                stream: _cast.devicesStream,
                initialData: _cast.devices,
                builder: (context, devSnap) {
                  final devices = devSnap.data ?? const <CastDevice>[];
                  if (devices.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          const AnimatedSagaMark(
                              size: 22, state: SagaMarkState.buffering),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Searching for Cast devices on your network…',
                              style: TextStyle(
                                  color: SagaColors.fgMuted, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final device in devices)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.tv_outlined,
                              color: SagaColors.fgMuted),
                          title: Text(device.name,
                              style: TextStyle(color: SagaColors.fg)),
                          onTap: () {
                            _pendingLoad = true;
                            _cast.selectDevice(device);
                          },
                        ),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
