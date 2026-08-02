/// A recorded loudness trace used to preview the Reactive mark motion in
/// Settings when nothing is playing.
///
/// **Why recorded and not synthesised.** A livelier hand-made envelope would
/// make the preview lie: the user picks Reactive because it looked alive, then
/// real quiet narration renders much like Gentle. These are the values the tap
/// genuinely emitted — post-gain, post-clamp — so the preview shows what
/// Reactive actually does, quiet passages included.
///
/// **Empty until captured.** With an empty trace [CannedAudioLevel] reports
/// `isLive: false`, so the preview honestly degrades to the Gentle envelope —
/// the same thing the live mark does when the tap is silent. It shows no fake
/// motion in the meantime.
///
/// **To capture it** (needs a device, a debug build and a playing book):
///
///  1. `flutter run` a debug build and start any audiobook.
///  2. Settings → Player animation → **Capture RMS trace** (debug-only button).
///     Set the animation sync delay to 0 first, or the A2DP offset is baked in.
///  3. The captured snippet is printed to the console and copied into the
///     sheet. Paste it over the two constants below.
///  4. Trim both ends into a pause so the loop seam doesn't visibly jump, and
///     keep a passage with real dynamics — sentence, breath, sentence — rather
///     than a uniformly loud stretch. ~4–6 s is plenty.
///
/// No audio is embedded: a few hundred loudness scalars are not recoverable
/// speech.
library;

/// Gap between samples, in ms — the native tap's cadence (~30 Hz). Replayed at
/// this rate rather than the mark's 60 fps so the dynamics match the real
/// source.
const int kSpeechTraceIntervalMs = 33;

/// Display-ready loudness samples, 0..1. Empty until captured — see above.
const List<double> kSpeechTrace = <double>[];
