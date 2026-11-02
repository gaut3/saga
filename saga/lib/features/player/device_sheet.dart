import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/cast/cast_service.dart';
import '../../core/theme/saga_theme.dart';
import '../../shared/widgets/saga_mark.dart' show AnimatedSagaMark, SagaMarkState;
import '../../shared/widgets/saga_sheet.dart';
import '../../shared/widgets/saga_toast.dart';
import 'player_provider.dart';
import 'player_service.dart';

/// "Play on": this phone, or a Cast device (frame 04 of the Vellum handoff).
/// Picking a device hands the book to it from where the phone is; picking
/// This phone brings it back, still playing if the TV was.
void showDeviceSheet(BuildContext context,
    {required AudioPlayerService service}) {
  showSagaSheet<void>(context, (_) => _DeviceSheet(service: service),
      scrollable: false);
}

class _DeviceSheet extends ConsumerStatefulWidget {
  final AudioPlayerService service;
  const _DeviceSheet({required this.service});

  @override
  ConsumerState<_DeviceSheet> createState() => _DeviceSheetState();
}

class _DeviceSheetState extends ConsumerState<_DeviceSheet> {
  late final CastService _cast = widget.service.cast;
  final _subs = <StreamSubscription<Object?>>[];
  // The slider's own value while dragging; the receiver's otherwise.
  double? _dragVolume;
  DateTime _volumeSentAt = DateTime(0);

  @override
  void initState() {
    super.initState();
    _cast.startDiscovery();
    void rebuild(Object? _) {
      if (mounted) setState(() {});
    }

    _subs
      ..add(_cast.stateStream.listen(rebuild))
      ..add(_cast.devicesStream.listen(rebuild))
      ..add(_cast.statusStream.listen(rebuild))
      // Session failures, and the handler's own (no server, a refused
      // load): without this the sheet silently snaps back to the list.
      ..add(_cast.errorStream.listen((reason) {
        if (mounted) {
          showSagaToast(context, 'Cast: $reason', isError: true);
        }
      }));
    widget.service.casting.addListener(_onCasting);
  }

  void _onCasting() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    widget.service.casting.removeListener(_onCasting);
    _cast.stopDiscovery(); // active scanning costs battery — only while open
    super.dispose();
  }

  void _setVolume(double v, {bool end = false}) {
    setState(() => _dragVolume = end ? null : v);
    // Every drag event would be a network command; a few a second is plenty.
    final now = DateTime.now();
    if (end || now.difference(_volumeSentAt) > const Duration(milliseconds: 150)) {
      _volumeSentAt = now;
      widget.service.setCastVolume(v);
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final state = _cast.state;
    final connected = state == CastState.connected;
    final casting = service.casting.value;
    final deviceName = _cast.deviceName;
    final others = _cast.devices
        .where((d) => !(connected && d.name == deviceName))
        .toList();

    final rows = <Widget>[
      _DeviceRow(
        icon: Icons.smartphone_outlined,
        title: 'This phone',
        subtitle: 'Speaker or headphones',
        selected: state == CastState.idle,
        onTap: () async {
          if (state != CastState.idle) {
            await service.stopCasting(resumeHere: true);
          }
          if (context.mounted) Navigator.pop(context);
        },
      ),
      if (connected)
        _DeviceRow(
          icon: Icons.tv_outlined,
          title: deviceName ?? 'Cast device',
          subtitle: casting ? 'Playing here' : 'Connected',
          selected: true,
          onTap: () {},
        ),
      if (state == CastState.connecting)
        _DeviceRow(
          leading: const AnimatedSagaMark(
              size: 22, state: SagaMarkState.buffering),
          title: 'Connecting…',
          selected: false,
          onTap: () {},
        ),
      for (final device in others)
        _DeviceRow(
          icon: Icons.tv_outlined,
          title: device.name,
          selected: false,
          onTap: () => service.castTo(device),
        ),
      if (others.isEmpty && !connected && state != CastState.connecting)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            children: [
              const SizedBox(
                width: 40,
                child: Center(
                  child: AnimatedSagaMark(
                      size: 22, state: SagaMarkState.buffering),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Searching for Cast devices on your network…',
                  style: TextStyle(color: SagaColors.fgMuted, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SagaSheetTitle('Play on',
              padding: const EdgeInsets.fromLTRB(0, 4, 0, 4)),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(color: SagaColors.border, height: 1),
            rows[i],
          ],
          if (connected) ..._castControls(service),
        ],
      ),
    );
  }

  List<Widget> _castControls(AudioPlayerService service) {
    final volume =
        (_dragVolume ?? _cast.status?.deviceVolume ?? 0.5).clamp(0.0, 1.0);
    final sleep = ref.watch(sleepTimerProvider) == null
        ? null
        : ref.read(sleepTimerProvider.notifier).remaining;
    return [
      Divider(color: SagaColors.border, height: 1),
      const SizedBox(height: 16),
      Text('TV volume',
          style: TextStyle(color: SagaColors.fgMuted, fontSize: 14.5)),
      Semantics(
        label: 'TV volume',
        child: Slider(
          value: volume,
          activeColor: SagaColors.accent,
          inactiveColor: SagaColors.surfaceAlt,
          onChanged: (v) => _setVolume(v),
          onChangeEnd: (v) => _setVolume(v, end: true),
        ),
      ),
      if (service.casting.value)
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (sleep != null)
              _Chip('Sleep ${(sleep.inSeconds / 60).ceil()} min · on TV'),
            const _Chip('Counts in History'),
          ],
        ),
      const SizedBox(height: 12),
      Center(
        child: TextButton(
          onPressed: () async {
            await service.stopCasting();
            if (mounted) Navigator.pop(context);
          },
          style: TextButton.styleFrom(foregroundColor: SagaColors.fgMuted),
          child: const Text('Stop casting',
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
        ),
      ),
    ];
  }
}

/// A 56px "Play on" row: a 40px tile, the name, and a check when selected.
class _DeviceRow extends StatelessWidget {
  final IconData? icon;
  final Widget? leading;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _DeviceRow({
    this.icon,
    this.leading,
    required this.title,
    this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: selected ? SagaColors.accent : SagaColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: leading ??
                      Icon(icon,
                          size: 22,
                          color: selected
                              ? SagaColors.accentFg
                              : SagaColors.fgMuted),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color:
                              selected ? SagaColors.accentText : SagaColors.fg,
                          fontSize: 16,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                      if (subtitle != null)
                        Text(subtitle!,
                            style: TextStyle(
                                color: SagaColors.fgMuted, fontSize: 12.5)),
                    ],
                  ),
                ),
                if (selected)
                  Icon(Icons.check_rounded, color: SagaColors.accent, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  const _Chip(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: SagaColors.surfaceAlt,
        borderRadius: BorderRadius.circular(99),
      ),
      // fg, not fgMuted: the AA floors are pinned on bg and surface, and
      // this sits on surfaceAlt.
      child: Text(text, style: TextStyle(color: SagaColors.fg, fontSize: 12.5)),
    );
  }
}
