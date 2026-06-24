/**
 * Lightweight haptic feedback for touch devices.
 * Uses the Vibration API — silently no-ops on desktop / unsupported browsers.
 * Patterns are intentionally short so the app feels responsive, never buzzy.
 */

type HapticKind = 'tap' | 'select' | 'success' | 'warn' | 'error'

const PATTERNS: Record<HapticKind, number | number[]> = {
  tap: 8, // light confirm — switching tabs, pressing a primary button
  select: 12, // toggling a choice — RSVP, calendar day
  success: [14, 40, 24], // an event added, a quest marked done
  warn: [20, 30, 20],
  error: [40, 30, 40],
}

export function haptic(kind: HapticKind = 'tap') {
  if (typeof navigator === 'undefined' || !('vibrate' in navigator)) return
  try {
    navigator.vibrate(PATTERNS[kind])
  } catch {
    // some browsers throw when called outside a user gesture — ignore
  }
}
