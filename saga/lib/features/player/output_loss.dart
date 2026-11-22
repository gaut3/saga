// AudioDeviceType is marked experimental in audio_session. If a bump changes
// it, this file and its test fail to build, which is where it should show.
// ignore_for_file: experimental_member_use

import 'package:audio_session/audio_session.dart';

/// Outputs that are part of the phone itself. Audio routed to one of these is
/// audio the room can hear.
const _phoneOutputs = {
  AudioDeviceType.builtInSpeaker,
  AudioDeviceType.builtInSpeakerSafe,
  AudioDeviceType.builtInEarpiece,
  AudioDeviceType.telephony,
};

bool _isExternal(AudioDevice d) =>
    d.isOutput && !_phoneOutputs.contains(d.type);

/// Whether a change of outputs has left the phone playing out loud: an output
/// outside the phone went away and none is left (GitHub #31).
///
/// Android's "becoming noisy" signal is meant to say this, and Saga pauses on
/// it, but it doesn't come when Android Auto disconnects: the car link and its
/// Bluetooth drop and the book carries on from the phone's speaker. Saga sees
/// the outputs go, so it asks the question itself. Asking "did anything go?"
/// would pause the book when a watch disconnects or a screen recording ends;
/// "is anything outside the phone left?" doesn't.
///
/// [remaining] is the output list read after the change. `remoteSubmix` counts
/// as outside the phone: it's how Android Auto's audio shows up, and on a
/// wired connection with Bluetooth off it may be the only sign of the car.
bool leftOnlyPhoneOutputs({
  required Set<AudioDevice> removed,
  required Set<AudioDevice> remaining,
}) =>
    removed.any(_isExternal) && !remaining.any(_isExternal);
