import type { FoodResult, ScoreReason } from './food-search'

/**
 * Manual food entry — for the long tail the databases miss: homemade dinners,
 * leftovers, a friend's recipe, the bakery item with no barcode.
 *
 * We can't read an ingredient list we were never given, so the score is honest
 * about its inputs: it rewards what the user tells us (whole, home-cooked) and
 * what the macros reveal (fibre, protein), and it says so in the breakdown. No
 * hidden assumptions — every point is named, same as a scanned product.
 */

export type ManualKind = 'whole' | 'home' | 'packaged'

export type ManualInput = {
  name: string
  brand?: string
  /** Grams in one serving — the basis for everything entered below. */
  servingGrams: number
  /** The word shown on the portion picker, e.g. "bowl", "slice", "serving". */
  servingLabel: string
  kind: ManualKind
  /** Macros for ONE serving (not per 100g) — the natural way people think. */
  perServing: { calories: number; protein: number; carbs: number; fat: number; fibre: number }
}

const KIND_REASON: Record<ManualKind, ScoreReason> = {
  whole: { label: 'Whole, single-ingredient food', delta: 22 },
  home: { label: 'Home-cooked from scratch', delta: 14 },
  packaged: { label: 'Packaged / processed', delta: -10 },
}

function scoreManual(per100: { protein: number; fibre: number }, kind: ManualKind): {
  score: number
  reasons: ScoreReason[]
  badges: FoodResult['badges']
} {
  let score = 70
  const reasons: ScoreReason[] = []
  const badges: FoodResult['badges'] = []
  const add = (r: ScoreReason) => { score += r.delta; reasons.push(r) }

  add(KIND_REASON[kind])
  if (kind === 'whole') badges.push({ label: 'Whole Food', icon: '🌿', color: 'bg-green-100 text-green-800' })

  if (per100.fibre >= 5) { add({ label: 'High in fibre', delta: 5 }); badges.push({ label: 'High Fibre', icon: '💚', color: 'bg-teal-100 text-teal-800' }) }
  if (per100.protein >= 15) { add({ label: 'High in protein', delta: 4 }); badges.push({ label: 'High Protein', icon: '💪', color: 'bg-amber-100 text-amber-800' }) }

  return { score: Math.max(1, Math.min(100, score)), reasons, badges }
}

/** Turn manual input into a FoodResult, normalising macros to the per-100g shape. */
export function buildManualFood(input: ManualInput): FoodResult {
  const grams = Math.max(1, input.servingGrams)
  const f = 100 / grams // serving → per-100g
  const r1 = (n: number) => Math.round(n * f * 10) / 10
  const per100 = {
    calories: Math.round(input.perServing.calories * f),
    protein: r1(input.perServing.protein),
    carbs: r1(input.perServing.carbs),
    fat: r1(input.perServing.fat),
    fibre: r1(input.perServing.fibre),
  }
  const { score, reasons, badges } = scoreManual(per100, input.kind)

  return {
    food_name: input.name.trim(),
    brand: input.brand?.trim() || null,
    ...per100,
    score,
    badges,
    flags: [],
    reasons,
    manual: true,
    serving_grams: grams,
    serving_size: input.servingLabel.trim() || 'serving',
  }
}
