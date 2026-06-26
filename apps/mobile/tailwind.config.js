/** @type {import('tailwindcss').Config} */
// Hygge design tokens (NativeWind). Mirror src/theme.ts (JS tokens) — keep them in sync.
module.exports = {
  content: ['./src/**/*.{js,jsx,ts,tsx}'],
  presets: [require('nativewind/preset')],
  theme: {
    extend: {
      colors: {
        // Surfaces — warm linen first
        paper: {
          DEFAULT: '#fbfaf5',
          50: '#fbfaf5',
          100: '#f5f1e8',
          200: '#eae4d4',
          300: '#e1dbc9',
        },
        // Text — charcoal ink
        ink: {
          DEFAULT: '#2a2a28',
          2: '#5e5d56',
          3: '#8a887e',
        },
        // sky → slate blue-grey (brand / focus)
        sky: {
          400: '#a6b1b6',
          500: '#87959c',
          600: '#6b7b84',
          700: '#55636b',
          800: '#3e4d54',
        },
        // moss → dark pine (positive / primary action / completed)
        moss: {
          400: '#4f7053',
          500: '#3c5a40',
          600: '#3c5a40',
          700: '#2d4530',
          800: '#1f3022',
        },
        // honey → warmth (sparingly)
        honey: {
          600: '#b07d2b',
          700: '#8a5f1c',
        },
        // clay → warning / error only
        clay: {
          700: '#b0573a',
          800: '#8c4329',
        },
      },
      fontFamily: {
        // Loaded via expo-font; names must match the keys in the font loader.
        display: ['Spectral'],        // Spectral — wordmark, headings
        sans: ['SchibstedGrotesk'],   // Schibsted Grotesk — UI, body
        mono: ['GeistMono'],          // Geist Mono — every number
      },
    },
  },
  plugins: [],
}
