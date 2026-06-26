// Hygge tokens for use in JS (gradients, image maps, font names). Colours mirror
// tailwind.config.js — keep them in sync.
export const C = {
  paper: '#fbfaf5',
  paper100: '#f5f1e8',
  paper200: '#eae4d4',
  paper300: '#e1dbc9',
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

// "Around town" carousel — real St. Joseph places.
export type Collection = { name: string; blurb: string; image: number; kw: string[] | null }
export const COLLECTIONS: Collection[] = [
  { name: 'Downtown', blurb: 'Shops & cafés on Minnesota St', image: require('../assets/around-town/downtown.jpg'), kw: ['downtown', 'minnesota st', 'local blend', 'krewe', 'bo diddley', 'middy', 'college ave'] },
  { name: "Saint Ben's", blurb: 'College of Saint Benedict', image: require('../assets/around-town/saint-bens.jpg'), kw: ['saint ben', 'st. ben', 'st ben', 'csb', 'benedict', 'gorecki', 'campus'] },
  { name: 'Sacred Heart Chapel', blurb: 'The monastery & its dome', image: require('../assets/around-town/sacred-heart-chapel.jpg'), kw: ['chapel', 'sacred heart', 'monastery', 'mass', 'sisters'] },
  { name: "Saint John's", blurb: 'The Abbey in Collegeville', image: require('../assets/around-town/saint-johns-abbey.jpg'), kw: ['saint john', 'st. john', 'st john', 'sju', 'abbey', 'collegeville'] },
  { name: 'Wobegon Trail', blurb: 'Bike, walk & run the trail', image: require('../assets/around-town/wobegon-trail.jpg'), kw: ['wobegon', 'trail', 'bike', 'walk', 'run', 'ride', 'river', 'watab'] },
]

export function matchesKw(text: string, kw: string[] | null): boolean {
  if (!kw) return true
  const t = text.toLowerCase()
  return kw.some((k) => t.includes(k))
}
