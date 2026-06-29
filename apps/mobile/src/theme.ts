// Hygge tokens for use in JS (gradients, image maps, font names). Colours mirror
// tailwind.config.js — keep them in sync.
export const C = {
  paper: '#fbfaf5',
  paper100: '#f5f1e8',
  paper200: '#eae4d4',
  paper300: '#e1dbc9',
  // App page background — a soft, de-yellowed warm linen. Lighter and less
  // saturated than paper100 so white cards lift off it without a yellow cast.
  canvas: '#f1f0ec',
  ink: '#2a2a28',
  ink2: '#5e5d56',
  ink3: '#8a887e',
  moss700: '#2d4530',
  moss500: '#3c5a40',
  sky600: '#6b7b84',
  honey700: '#8a5f1c',
  clay700: '#b0573a',
  hairline: 'rgba(60,60,60,0.10)',
} as const

// Matches the web app's HAIRLINE border (1px rgba(0,0,0,0.07)).
export const HAIRLINE = 'rgba(0,0,0,0.07)'

// Vibrant graphics palette — rings, gauges, dots, accents. Brighter than the
// muted semantic accents so data viz reads with energy (Cal-AI-style colour).
export const GRAPH = {
  green: '#3f9b6e',
  greenDeep: '#2f7d57',
  amber: '#e6a23a',
  amberDeep: '#c98217',
  sky: '#5d8aa8',
  coral: '#e07a5f',
} as const

// Soft "floating card" lift — a warm semi-transparent shadow (not a hard border)
// so cards rise off the linen page. Borrowed craft from clean iOS dashboards,
// kept calm. Spread onto a card's outer (non-clipped) view.
export const CARD_SHADOW = {
  shadowColor: '#2a241c',
  shadowOpacity: 0.1,
  shadowRadius: 22,
  shadowOffset: { width: 0, height: 10 },
  elevation: 5,
} as const

// Font family names — must match the keys registered in _layout.tsx useFonts().
export const F = {
  display: 'Spectral',
  displaySemi: 'SpectralSemi',
  sans: 'Schibsted',
  sansMed: 'SchibstedMed',
  sansSemi: 'SchibstedSemi',
  sansBold: 'SchibstedBold',
  mono: 'GeistMono',
  monoMed: 'GeistMonoMed',
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
