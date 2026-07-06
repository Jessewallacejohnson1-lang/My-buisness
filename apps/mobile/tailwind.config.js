/** @type {import('tailwindcss').Config} */
// Design tokens (NativeWind). Mirror src/theme.ts (JS tokens) — keep them in sync.
module.exports = {
  content: ['./src/**/*.{js,jsx,ts,tsx}'],
  presets: [require('nativewind/preset')],
  theme: {
    extend: {
      colors: {
        // Surfaces — pure white + iOS system grays
        paper: {
          DEFAULT: '#FFFFFF',
          50: '#FFFFFF',
          100: '#F2F2F7',
          200: '#E5E5EA',
          300: '#D1D1D6',
        },
        // Text — WCAG 2.1 contrast on white (#FFFFFF):
        //   DEFAULT #000000 → 21:1   (primary, AAA)
        //   2       #3C3C43 →  9.4:1 (secondary, AAA)
        //   3       #8E8E93 →  3.5:1 (tertiary/placeholder ≥3 floor)
        // Keep in sync with the ink ramp + ratios in src/theme.ts.
        ink: {
          DEFAULT: '#000000',
          2: '#3C3C43',
          3: '#8E8E93',
        },
        // sky → system blue (links, focus)
        sky: {
          400: '#64B5F6',
          500: '#2196F3',
          600: '#007AFF',
          700: '#0062CC',
          800: '#004999',
        },
        // moss → coral accent (primary actions / brand). Mirrors C.moss700 in src/theme.ts.
        moss: {
          400: '#FFA294',
          500: '#FF8574',
          600: '#E0553F',
          700: '#FF6B57',
          800: '#C74533',
        },
        // clay → system red (errors only)
        clay: {
          700: '#FF3B30',
          800: '#D70015',
        },

        // shadcn / react-native-reusables semantic aliases
        border: 'rgba(0,0,0,0.08)',
        input: 'rgba(0,0,0,0.08)',
        ring: '#007AFF',                // sky-600 — focus
        background: '#F2F2F7',          // canvas
        foreground: '#000000',          // ink
        primary: { DEFAULT: '#FF6B57', foreground: '#FFFFFF' },   // coral (moss-700) / paper
        secondary: { DEFAULT: '#E5E5EA', foreground: '#000000' }, // paper-200 / ink
        muted: { DEFAULT: '#F2F2F7', foreground: '#8E8E93' },     // paper-100 / ink-3
        accent: { DEFAULT: '#F2F2F7', foreground: '#000000' },    // paper-100 / ink
        destructive: { DEFAULT: '#FF3B30', foreground: '#FFFFFF' }, // clay-700 / paper
        card: { DEFAULT: '#FFFFFF', foreground: '#000000' },      // paper / ink
        popover: { DEFAULT: '#FFFFFF', foreground: '#000000' },   // paper / ink
      },
      // Typography is the platform system font (SF Pro / Roboto) — no bundled UI
      // font. The one custom face in the app is the logo (HyggeLogoBadge, Atkinson
      // Hyperlegible), applied inline there, never through a utility class. Weight
      // comes from the numeric `font-medium`/`font-semibold`/`font-bold` utilities:
      // the system font carries every weight, so RN renders it natively.
      // `font-sans`/`font-mono` fall back to Tailwind's system stacks.
      //
      // Radius scale — named by px value so the class and the JS token never
      // drift (mirrors RADIUS in src/theme.ts). Extends, doesn't replace, the
      // Tailwind defaults, so existing `rounded-md/lg/xl/full` keep their values.
      //   rounded-sm8 (8)  small chips / insets
      //   rounded-md12 (12) inputs, buttons        ← control default
      //   rounded-lg16 (16) cards                  ← card default
      //   rounded-xl20 (20) full-bleed sheets / hero
      borderRadius: {
        sm8: '8px',
        md12: '12px',
        lg16: '16px',
        xl20: '20px',
      },
    },
  },
  plugins: [],
}
