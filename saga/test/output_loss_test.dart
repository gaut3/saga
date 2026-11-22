// GitHub #31: leaving Android Auto kept the book playing from the phone's
// speaker, because Android never sent "becoming noisy". The route log showed
// the outputs going; leftOnlyPhoneOutputs decides from that whether to pause.

// ignore_for_file: experimental_member_use

import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saga/features/player/output_loss.dart';

AudioDevice _out(AudioDeviceType type, [String id = '']) => AudioDevice(
    id: id.isEmpty ? type.name : id,
    name: type.name,
    isInput: false,
    isOutput: true,
    type: type);

final speaker = _out(AudioDeviceType.builtInSpeaker);
final earpiece = _out(AudioDeviceType.builtInEarpiece);
final a2dp = _out(AudioDeviceType.bluetoothA2dp);
final sco = _out(AudioDeviceType.bluetoothSco);
final submix = _out(AudioDeviceType.remoteSubmix);
final wired = _out(AudioDeviceType.wiredHeadphones);

void main() {
  test('Android Auto disconnecting, as in the #31 log: pauses', () {
    // Bluetooth goes first, then the car link.
    expect(
        leftOnlyPhoneOutputs(
            removed: {sco, a2dp}, remaining: {speaker, earpiece, submix}),
        isFalse,
        reason: 'the car link is still there');
    expect(
        leftOnlyPhoneOutputs(removed: {submix}, remaining: {speaker, earpiece}),
        isTrue);
  });

  test('Bluetooth headphones switched off: pauses', () {
    expect(
        leftOnlyPhoneOutputs(
            removed: {a2dp, sco}, remaining: {speaker, earpiece}),
        isTrue);
  });

  test('a call ending in the car leaves its audio there: keeps playing', () {
    expect(
        leftOnlyPhoneOutputs(
            removed: {sco}, remaining: {speaker, earpiece, a2dp}),
        isFalse);
  });

  test('the hands-free link never counts: it carries calls, not the book', () {
    // Mid-drive blip on a car with A2DP (the 2026-11-20 log).
    expect(
        leftOnlyPhoneOutputs(removed: {sco}, remaining: {speaker, a2dp}),
        isFalse);
    // Getting in: SCO drops 2 ms before A2DP is listed (2026-11-21 21:38).
    expect(leftOnlyPhoneOutputs(removed: {sco}, remaining: {speaker}),
        isFalse);
    // Headphones switched off with their hands-free link listed last.
    expect(leftOnlyPhoneOutputs(removed: {a2dp}, remaining: {speaker, sco}),
        isTrue);
  });

  test('one of two Bluetooth devices going: keeps playing on the other', () {
    expect(
        leftOnlyPhoneOutputs(
            removed: {_out(AudioDeviceType.bluetoothA2dp, 'watch')},
            remaining: {speaker, a2dp}),
        isFalse);
    expect(
        leftOnlyPhoneOutputs(removed: {a2dp}, remaining: {speaker, wired}),
        isFalse);
  });

  test('only phone outputs changing: keeps playing', () {
    expect(
        leftOnlyPhoneOutputs(removed: {earpiece}, remaining: {speaker}),
        isFalse);
  });

  test('an input going is not an output going', () {
    final mic = AudioDevice(
        id: 'mic',
        name: 'mic',
        isInput: true,
        isOutput: false,
        type: AudioDeviceType.headsetMic);
    expect(leftOnlyPhoneOutputs(removed: {mic}, remaining: {speaker}),
        isFalse);
  });
}
