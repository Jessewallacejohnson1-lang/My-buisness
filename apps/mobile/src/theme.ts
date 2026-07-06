// Design tokens for use in JS (gradients, image maps, font names). Colours mirror
// tailwind.config.js — keep them in sync.
//
// Ink ramp — WCAG 2.1 contrast on white (#FFFFFF):
//   ink   #000000  → 21:1   (primary — AAA)
//   ink2  #3C3C43  →  9.4:1 (secondary — AAA)
//   ink3  #8E8E93  →  3.5:1 (tertiary/placeholder — ≥3 floor)
export const C = {
  paper: '#FFFFFF',
  paper100: '#F2F2F7',
  paper200: '#E5E5EA',
  paper300: '#D1D1D6',
  // iOS-style system grouped background — cards (paper) lift off it cleanly.
  canvas: '#F2F2F7',
  ink: '#000000',
  ink2: '#3C3C43',
  ink3: '#8E8E93',
  // Coral accent — brand + primary actions + live/tappable. Mirrors the iOS app's
  // Hue.accent (#FF6B57) so both apps read the same. Sits on white surfaces across
  // every screen. Coral-on-white is a warm, intentionally lower-contrast look; white
  // button labels stay semibold to hold legibility. (Keys kept as `moss*` to avoid
  // churning ~40 call sites — prefer the `accent*` aliases in new code.)
  moss700: '#FF6B57',  // coral — primary actions / brand accent
  moss500: '#E0553F',  // deeper coral — secondary accents, dots
  accent: '#FF6B57',   // alias for coral (prefer in new code)
  accentPressed: '#E0553F', // deeper coral — pressed / secondary
  sky600: '#007AFF',   // system blue — location links, focus (kept: better text contrast than coral)
  clay700: '#FF3B30',  // system red — errors
  hairline: 'rgba(0,0,0,0.08)',
} as const

// Radius scale — the four corner radii the system uses, named by their px value
// so a class (`rounded-md12`) and a JS style (`borderRadius: RADIUS.md`) always
// agree. Mirrors `borderRadius` in tailwind.config.js. Defaults: inputs/buttons
// use `md` (12), cards use `lg` (16), full-bleed sheets/hero use `xl` (20),
// small chips/insets use `sm` (8). Pills are `rounded-full`, not part of this scale.
export const RADIUS = { sm: 8, md: 12, lg: 16, xl: 20 } as const

// Matches the web app's HAIRLINE border (1px rgba(0,0,0,0.07)).
export const HAIRLINE = 'rgba(0,0,0,0.07)'
// A lighter hairline — the thin half of the almanac masthead double-rule and the
// vertical dividers in the Today-bar readout. Deliberately fainter than HAIRLINE.
export const HAIRLINE_LIGHT = 'rgba(0,0,0,0.04)'

// Vibrant graphics palette — rings, gauges, dots. Brighter than the muted
// semantic accents so data viz reads with energy (used by WeekStrip / DayTimeline).
// Pruned 2026-06: `sky`, `coral`, `amberDeep` were verified zero-ref dead
// tokens. Only the live keys remain — add back deliberately if a graphic needs them.
export const GRAPH = {
  green: '#3f9b6e',
  greenDeep: '#2f7d57',
  amber: '#e6a23a',
} as const

// CARD_SHADOW — the single elevation in the system. One clean neutral lift
// so cards rise off the gray canvas; everything else stays flat.
// Spread onto a card's outer (non-clipped) view.
export const CARD_SHADOW = {
  shadowColor: '#000000',
  shadowOpacity: 0.08,
  shadowRadius: 20,
  shadowOffset: { width: 0, height: 8 },
  elevation: 4,
} as const

// Type weights for the platform system font (SF Pro on iOS, Roboto on Android).
// The app ships no bundled UI font — the only custom face is the logo (see
// HyggeLogoBadge). The system font carries every weight natively, so hierarchy is
// expressed through `fontWeight`; RN renders the real weight (no synthetic
// bolding). Consumed as `fontWeight: F.sansSemi`, so existing ternaries like
// `fontWeight: on ? F.sansSemi : F.sansMed` keep working unchanged. The
// display/mono keys are kept as readable aliases even though one system family
// now sits underneath them all.
export const F = {
  display: '700',
  displaySemi: '600',
  sans: '400',
  sansMed: '500',
  sansSemi: '600',
  sansBold: '700',
  mono: '400',
  monoMed: '500',
} as const

// Real-photo weather backdrops, bundled as assets.
export const WEATHER_IMAGES = {
  clearDay: require('../assets/weather/clear-day.jpg'),
  clearNight: require('../assets/weather/clear-night.jpg'),
  clouds: require('../assets/weather/clouds.jpg'),
  overcast: require('../assets/weather/overcast.jpg'),
  rain: require('../assets/weather/rain.png'),
  snow: require('../assets/weather/snow.jpg'),
  fog: require('../assets/weather/fog.jpg'),
  storm: require('../assets/weather/storm.jpg'),
} as const

export type WeatherKey = keyof typeof WEATHER_IMAGES

// "Around town" carousel — real St. Joseph places. Content lives in data/places.ts;
// re-exported here so existing import paths (`from '../theme'`) keep working.
export { COLLECTIONS, matchesKw, type Collection } from './data/places'
