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

        // shadcn / react-native-reusables semantic aliases — mapped onto Hygge
        // tokens so RNR components (`bg-primary`, `text-foreground`, …) render
        // on-brand. These are aliases, not new colors; keep them in sync above.
        border: 'rgba(0,0,0,0.07)',     // border-black/[0.07]
        input: 'rgba(0,0,0,0.07)',
        ring: '#6b7b84',                // sky-600 — focus
        background: '#fbfaf5',          // paper
        foreground: '#2a2a28',          // ink
        primary: { DEFAULT: '#2d4530', foreground: '#fbfaf5' },   // moss-700 / paper
        secondary: { DEFAULT: '#eae4d4', foreground: '#2a2a28' }, // paper-200 / ink
        muted: { DEFAULT: '#f5f1e8', foreground: '#8a887e' },     // paper-100 / ink-3
        accent: { DEFAULT: '#f5f1e8', foreground: '#2a2a28' },    // paper-100 / ink
        destructive: { DEFAULT: '#b0573a', foreground: '#fbfaf5' }, // clay-700 / paper
        card: { DEFAULT: '#fbfaf5', foreground: '#2a2a28' },     // paper / ink
        popover: { DEFAULT: '#fbfaf5', foreground: '#2a2a28' },  // paper / ink
      },
      fontFamily: {
        // Names MUST match the expo-font useFonts() keys in src/app/_layout.tsx.
        // RN registers each weight as its own family (no synthetic bolding), so we
        // expose a class per weight — `font-sans-semibold` etc. — instead of
        // relying on `font-semibold` (which RN can't synthesize on a 400-only face).
        display: ['Spectral'],            // Spectral 700 — wordmark, H1/hero
        'display-semi': ['SpectralSemi'], // Spectral 600 — softer headings
        sans: ['Schibsted'],              // Schibsted 400 — UI body (default)
        'sans-medium': ['SchibstedMed'],  // 500
        'sans-semibold': ['SchibstedSemi'], // 600 — labels, buttons
        'sans-bold': ['SchibstedBold'],   // 700
        mono: ['GeistMono'],              // Geist Mono 400 — every number
        'mono-medium': ['GeistMonoMed'],  // 500
      },
    },
  },
  plugins: [],
}
