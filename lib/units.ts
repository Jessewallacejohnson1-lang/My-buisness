import type { FoodResult } from './food-search'

/**
 * Portion units, resolved to grams.
 *
 * Grams are the source of truth — every food's nutrition is stored per 100g and
 * scaled by mass (see `scaleFood`). This module turns the units people actually
 * think in (oz, cups, "1 medium") into grams so the portion picker can offer
 * them without the rest of the app caring.
 *
 * Two kinds of unit:
 *  - **Exact** — grams and ounces are pure mass conversions, correct for any food.
 *  - **Approximate** — cups/tbsp/tsp are volume; without per-food density we use a
 *    water-like approximation and label it "≈". A food's *own* natural serving
 *    ("1 medium", "1 slice", "1 cup cooked") is exact when we know its gram weight.
 */

export const GRAMS_PER_OZ = 28.3495

/** Generic volume→mass approximations (water density). Labelled "≈" in the UI. */
const VOLUME_GRAMS = { cup: 240, tbsp: 15, tsp: 5 } as const

export type UnitOption = {
  key: string
  /** What the user sees in the dropdown, e.g. "grams", "oz", "medium", "cup ≈". */
  label: string
  /** Grams in a single count of this unit. */
  gramsPer: number
  /** Whether fractional counts make sense (1.5 cups yes, 1.5 grams no). */
  decimal: boolean
  /** True when the gram weight is an approximation, not exact for this food. */
  approx?: boolean
}

const GRAM: UnitOption = { key: 'g', label: 'grams', gramsPer: 1, decimal: false }
const OZ: UnitOption = { key: 'oz', label: 'oz', gramsPer: GRAMS_PER_OZ, decimal: true }

/**
 * The unit choices to offer for a given food, best-first.
 *
 * If the food carries a natural serving (a banana's "1 medium" = 118g, a bread's
 * "1 slice" = 28g), that leads — it's the most intuitive and it's exact. Grams and
 * oz always follow as universal fallbacks, then the generic volume approximations.
 */
export function unitOptions(food: Pick<FoodResult, 'serving_grams' | 'serving_size'>): UnitOption[] {
  const opts: UnitOption[] = []

  if (food.serving_grams && food.serving_grams > 0) {
    const word = (food.serving_size || 'serving').trim()
    opts.push({ key: 'serving', label: word, gramsPer: food.serving_grams, decimal: true })
  }

  opts.push(GRAM, OZ)

  // Don't double up if the natural serving is already volume-named (e.g. "cup").
  const naturalWord = (food.serving_size || '').toLowerCase()
  for (const [key, grams] of Object.entries(VOLUME_GRAMS)) {
    if (naturalWord.includes(key)) continue
    opts.push({ key, label: `${key} ≈`, gramsPer: grams, decimal: true, approx: true })
  }

  return opts
}

/** Grams for `count` of a unit, clamped to a sane minimum. */
export function gramsFor(count: number, unit: UnitOption): number {
  return Math.max(1, Math.round(count * unit.gramsPer))
}

/** Round a count for display: whole numbers stay whole, fractions keep 1 decimal. */
export function roundCount(n: number): number {
  return Math.round(n * 10) / 10
}
