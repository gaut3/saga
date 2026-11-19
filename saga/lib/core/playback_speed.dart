/// Playback speed: the presets the picker lists, the range and step its
/// fine-tune row moves in, and the one label every screen prints.
///
/// Speeds are held as twentieths (0.05 steps) so that stepping can't drift:
/// 0.75 + 0.05 + 0.05 in doubles is 0.8500000000000001, which matches no
/// preset and prints as itself.
library;

const kSpeedPresets = [0.75, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0];
const kMinSpeed = 0.5;
const kMaxSpeed = 3.0;

const _stepsPerUnit = 20; // 0.05

/// [speed] on the 0.05 grid, inside the range. A speed that isn't a number
/// (a damaged setting) is 1.0 rather than an end of the range.
double snapSpeed(double speed) {
  if (!speed.isFinite) return 1.0;
  return (speed.clamp(kMinSpeed, kMaxSpeed) * _stepsPerUnit).round() /
      _stepsPerUnit;
}

/// [speed] moved by [steps] of 0.05, stopping at the ends of the range.
double stepSpeed(double speed, int steps) => snapSpeed(
    ((snapSpeed(speed) * _stepsPerUnit).round() + steps) / _stepsPerUnit);

/// "1.0", "0.85", "1.25" — without the × or x, which differs by place.
String fmtSpeed(double speed) => snapSpeed(speed).toString();
