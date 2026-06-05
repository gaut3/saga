// SagaMark.tsx — React component for the Saga logo mark.
// The mark is "stacked spines" — three book-spine rectangles
// of varying heights that also read as an audio level meter.
//
// Props
//   size     pixel size (square). Default 40.
//   theme    "cream" | "ink" | "terra" — overrides theme tokens.
//            Omit to inherit from CSS custom properties on the
//            nearest ancestor.
//   title    accessible label (default "Saga"). Set to "" for
//            decorative usage.

import * as React from "react";

type Theme = "cream" | "ink" | "terra";

type Props = {
  size?: number;
  theme?: Theme;
  title?: string;
  className?: string;
  /**
   * Animation state. Requires saga-mark-animations.css to be loaded.
   *   "playing"   — VU-meter pulse, each spine has its own rhythm
   *   "breathing" — gentle alive affordance (splash, idle)
   *   "loading"   — staggered fill, use during buffering/sync
   *   "paused"    — static logo (default)
   */
  state?: "playing" | "breathing" | "loading" | "paused";
};

const THEME_COLORS: Record<Theme, { side: string; middle: string; sideDot: string; midDot: string }> = {
  cream: { side: "#1E1410", middle: "#C25A3A", sideDot: "#C25A3A", midDot: "#F4EAD8" },
  ink:   { side: "#F4EAD8", middle: "#E0A050", sideDot: "#E0A050", midDot: "#1E1410" },
  terra: { side: "#F4EAD8", middle: "#1E1410", sideDot: "#1E1410", midDot: "#F4EAD8" },
};

export function SagaMark({ size = 40, theme, title = "Saga", className, state = "paused" }: Props) {
  // When a theme prop is passed, use its concrete colors.
  // When omitted, defer to CSS custom properties so the mark
  // automatically follows the surrounding theme.
  const t = theme ? THEME_COLORS[theme] : null;
  const side    = t ? t.side    : "var(--saga-mark-side, #1E1410)";
  const middle  = t ? t.middle  : "var(--saga-mark-middle, #C25A3A)";
  const sideDot = t ? t.sideDot : "var(--saga-mark-middle, #C25A3A)";
  const midDot  = t ? t.midDot  : "var(--saga-bg, #F4EAD8)";

  const cls = ["saga-mark", className].filter(Boolean).join(" ");
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 200 200"
      fill="none"
      role={title ? "img" : "presentation"}
      aria-label={title || undefined}
      className={cls}
      data-state={state}
    >
      {title ? <title>{title}</title> : null}
      <rect className="spine s-left"  x="30"  y="56" width="32" height="100" rx="4" fill={side} />
      <rect className="spine s-mid"   x="74"  y="36" width="32" height="140" rx="4" fill={middle} />
      <rect className="spine s-right" x="118" y="68" width="32" height="80"  rx="4" fill={side} />
      {/* book "title lines" */}
      <rect x="38"  y="74" width="16" height="2" fill={sideDot} opacity="0.7" />
      <rect x="38"  y="82" width="10" height="2" fill={sideDot} opacity="0.7" />
      <rect x="126" y="84" width="16" height="2" fill={sideDot} opacity="0.7" />
      <rect x="126" y="92" width="10" height="2" fill={sideDot} opacity="0.7" />
      <rect x="82"  y="58" width="16" height="2" fill={midDot}  opacity="0.5" />
      <rect x="82"  y="66" width="10" height="2" fill={midDot}  opacity="0.5" />
    </svg>
  );
}

// ─────────────────────────────────────────────────────────────
// SagaWordmark — the geometric sans wordmark "saga ▶".
// Renders as live text so it stays crisp at any size and is
// selectable / accessible. Requires Manrope 800 to be loaded.

type WordmarkProps = {
  size?: number;          // font-size in px (default 40)
  theme?: Theme;
  className?: string;
};

export function SagaWordmark({ size = 40, theme, className }: WordmarkProps) {
  const inkColor    = theme === "ink"   ? "#F4EAD8"
                    : theme === "terra" ? "#F4EAD8"
                    : theme === "cream" ? "#1E1410"
                    : "var(--saga-fg, #1E1410)";
  const accentColor = theme === "ink"   ? "#E0A050"
                    : theme === "terra" ? "#1E1410"
                    : theme === "cream" ? "#C25A3A"
                    : "var(--saga-accent, #C25A3A)";

  return (
    <span
      className={className}
      style={{
        fontFamily: "Manrope, system-ui, sans-serif",
        fontWeight: 800,
        fontSize: size,
        letterSpacing: "-0.055em",
        lineHeight: 1,
        color: inkColor,
        display: "inline-flex",
        alignItems: "center",
        gap: size * 0.14,
      }}
      aria-label="Saga"
    >
      saga
      <svg
        width={size * 0.42}
        height={size * 0.42}
        viewBox="0 0 40 40"
        aria-hidden="true"
      >
        <path d="M8 4 L34 20 L8 36 Z" fill={accentColor} />
      </svg>
    </span>
  );
}

// ─────────────────────────────────────────────────────────────
// SagaLockup — mark + wordmark, horizontal, baseline-aligned.

type LockupProps = {
  size?: number;          // wordmark font-size in px (mark sizes match)
  theme?: Theme;
  className?: string;
};

export function SagaLockup({ size = 40, theme, className }: LockupProps) {
  return (
    <span
      className={className}
      style={{ display: "inline-flex", alignItems: "center", gap: size * 0.3 }}
      aria-label="Saga"
    >
      <SagaMark size={size * 1.15} theme={theme} title="" />
      <SagaWordmark size={size} theme={theme} />
    </span>
  );
}
