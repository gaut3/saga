/// Pure smart-resume rewind curve: ~50 ms per second away (5 s per 100 s),
/// no rewind under 5 s away, capped at 60 s. The single tunable definition —
/// `AudioPlayerService._resumeRewindMs` delegates here for both the live
/// resume-after-pause path and the resume-after-load path, so the two curves
/// can never drift apart.
int resumeRewindMs(int awaySeconds, {required bool enabled}) {
  if (!enabled) return 0;
  return awaySeconds <= 5 ? 0 : (awaySeconds * 50).clamp(0, 60000);
}
