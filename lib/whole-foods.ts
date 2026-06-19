import type { FoodResult } from './food-search'

/**
 * Curated whole-food database — generic, single-ingredient basics that Open
 * Food Facts handles badly (search "eggs" there and you get random branded
 * cartons). These are the foods the clean score is meant to reward, so they're
 * scored as NOVA-1 whole foods. All nutrition is per 100g, matching how
 * Open Food Facts results are logged.
 */

type Macros = {
  kcal: number
  p: number // protein
  c: number // carbs
  f: number // fat
  fib: number // fibre
}

type WholeFoodSeed = {
  name: string
  /** Extra search terms / common aliases (e.g. "maize" → Sweet corn). */
  aka?: string[]
  m: Macros
  /** Manual score override; otherwise derived from macros. */
  score?: number
}

const SEED: WholeFoodSeed[] = [
  // Protein
  { name: 'Egg', aka: ['eggs'], m: { kcal: 143, p: 13, c: 1.1, f: 10, fib: 0 } },
  { name: 'Egg white', aka: ['egg whites'], m: { kcal: 52, p: 11, c: 0.7, f: 0.2, fib: 0 } },
  { name: 'Chicken breast', aka: ['chicken'], m: { kcal: 165, p: 31, c: 0, f: 3.6, fib: 0 } },
  { name: 'Chicken thigh', m: { kcal: 209, p: 26, c: 0, f: 11, fib: 0 } },
  { name: 'Salmon', m: { kcal: 208, p: 20, c: 0, f: 13, fib: 0 } },
  { name: 'Tuna (canned in water)', aka: ['tuna'], m: { kcal: 116, p: 26, c: 0, f: 1, fib: 0 } },
  { name: 'Shrimp', aka: ['prawns'], m: { kcal: 99, p: 24, c: 0.2, f: 0.3, fib: 0 } },
  { name: 'Lean ground beef (90/10)', aka: ['beef', 'mince'], m: { kcal: 217, p: 26, c: 0, f: 12, fib: 0 }, score: 84 },
  { name: 'Turkey breast', aka: ['turkey'], m: { kcal: 135, p: 30, c: 0, f: 1, fib: 0 } },
  { name: 'Tofu (firm)', aka: ['tofu'], m: { kcal: 144, p: 17, c: 3, f: 9, fib: 2 } },
  { name: 'Greek yogurt (plain, nonfat)', aka: ['greek yogurt', 'yoghurt'], m: { kcal: 59, p: 10, c: 3.6, f: 0.4, fib: 0 } },
  { name: 'Cottage cheese', m: { kcal: 98, p: 11, c: 3.4, f: 4.3, fib: 0 } },

  // Grains & starches
  { name: 'White rice (cooked)', aka: ['rice'], m: { kcal: 130, p: 2.7, c: 28, f: 0.3, fib: 0.4 }, score: 80 },
  { name: 'Brown rice (cooked)', m: { kcal: 123, p: 2.7, c: 26, f: 1, fib: 1.6 } },
  { name: 'Rolled oats (dry)', aka: ['oats', 'oatmeal', 'porridge'], m: { kcal: 389, p: 17, c: 66, f: 7, fib: 11 } },
  { name: 'Quinoa (cooked)', m: { kcal: 120, p: 4.4, c: 21, f: 1.9, fib: 2.8 } },
  { name: 'Sweet potato', aka: ['yam'], m: { kcal: 86, p: 1.6, c: 20, f: 0.1, fib: 3 } },
  { name: 'Potato', aka: ['potatoes'], m: { kcal: 77, p: 2, c: 17, f: 0.1, fib: 2.2 } },
  { name: 'Whole wheat bread', aka: ['bread', 'wholemeal bread'], m: { kcal: 247, p: 13, c: 41, f: 3.4, fib: 7 }, score: 78 },

  // Legumes
  { name: 'Black beans (cooked)', aka: ['black beans'], m: { kcal: 132, p: 8.9, c: 24, f: 0.5, fib: 8.7 } },
  { name: 'Lentils (cooked)', aka: ['lentils', 'dal'], m: { kcal: 116, p: 9, c: 20, f: 0.4, fib: 7.9 } },
  { name: 'Chickpeas (cooked)', aka: ['chickpeas', 'garbanzo'], m: { kcal: 164, p: 8.9, c: 27, f: 2.6, fib: 7.6 } },

  // Fruit
  { name: 'Banana', aka: ['bananas'], m: { kcal: 89, p: 1.1, c: 23, f: 0.3, fib: 2.6 } },
  { name: 'Apple', aka: ['apples'], m: { kcal: 52, p: 0.3, c: 14, f: 0.2, fib: 2.4 } },
  { name: 'Orange', aka: ['oranges'], m: { kcal: 47, p: 0.9, c: 12, f: 0.1, fib: 2.4 } },
  { name: 'Blueberries', m: { kcal: 57, p: 0.7, c: 14, f: 0.3, fib: 2.4 } },
  { name: 'Strawberries', m: { kcal: 32, p: 0.7, c: 7.7, f: 0.3, fib: 2 } },
  { name: 'Avocado', m: { kcal: 160, p: 2, c: 9, f: 15, fib: 7 } },
  { name: 'Grapes', m: { kcal: 69, p: 0.7, c: 18, f: 0.2, fib: 0.9 } },

  // Vegetables
  { name: 'Broccoli', m: { kcal: 34, p: 2.8, c: 7, f: 0.4, fib: 2.6 } },
  { name: 'Spinach', m: { kcal: 23, p: 2.9, c: 3.6, f: 0.4, fib: 2.2 } },
  { name: 'Carrot', aka: ['carrots'], m: { kcal: 41, p: 0.9, c: 10, f: 0.2, fib: 2.8 } },
  { name: 'Bell pepper', aka: ['capsicum', 'pepper'], m: { kcal: 31, p: 1, c: 6, f: 0.3, fib: 2.1 } },
  { name: 'Tomato', aka: ['tomatoes'], m: { kcal: 18, p: 0.9, c: 3.9, f: 0.2, fib: 1.2 } },
  { name: 'Cucumber', m: { kcal: 15, p: 0.7, c: 3.6, f: 0.1, fib: 0.5 } },
  { name: 'Sweet corn', aka: ['corn', 'maize'], m: { kcal: 86, p: 3.2, c: 19, f: 1.2, fib: 2.7 } },

  // Nuts & fats
  { name: 'Almonds', m: { kcal: 579, p: 21, c: 22, f: 50, fib: 12.5 }, score: 88 },
  { name: 'Walnuts', m: { kcal: 654, p: 15, c: 14, f: 65, fib: 6.7 }, score: 86 },
  { name: 'Peanut butter', m: { kcal: 588, p: 25, c: 20, f: 50, fib: 6 }, score: 82 },
  { name: 'Olive oil', m: { kcal: 884, p: 0, c: 0, f: 100, fib: 0 }, score: 82 },

  // Dairy
  { name: 'Whole milk', aka: ['milk'], m: { kcal: 61, p: 3.2, c: 4.8, f: 3.3, fib: 0 }, score: 85 },
  { name: 'Cheddar cheese', aka: ['cheese'], m: { kcal: 403, p: 25, c: 1.3, f: 33, fib: 0 }, score: 80 },
]

/**
 * Natural serving size per food: grams + the unit word shown in the portion
 * picker (e.g. "1 egg (50g)"). Anything not listed falls back to 100g.
 */
const SERVING: Record<string, { g: number; unit: string }> = {
  'Egg': { g: 50, unit: 'egg' },
  'Egg white': { g: 33, unit: 'white' },
  'Chicken breast': { g: 120, unit: 'breast' },
  'Chicken thigh': { g: 100, unit: 'thigh' },
  'Salmon': { g: 150, unit: 'fillet' },
  'Tuna (canned in water)': { g: 120, unit: 'can' },
  'Shrimp': { g: 85, unit: 'serving' },
  'Lean ground beef (90/10)': { g: 113, unit: 'serving (4oz)' },
  'Turkey breast': { g: 120, unit: 'serving' },
  'Tofu (firm)': { g: 100, unit: 'serving' },
  'Greek yogurt (plain, nonfat)': { g: 170, unit: 'cup' },
  'Cottage cheese': { g: 113, unit: '½ cup' },
  'White rice (cooked)': { g: 158, unit: 'cup' },
  'Brown rice (cooked)': { g: 195, unit: 'cup' },
  'Rolled oats (dry)': { g: 40, unit: '½ cup' },
  'Quinoa (cooked)': { g: 185, unit: 'cup' },
  'Sweet potato': { g: 130, unit: 'medium' },
  'Potato': { g: 173, unit: 'medium' },
  'Whole wheat bread': { g: 28, unit: 'slice' },
  'Black beans (cooked)': { g: 86, unit: '½ cup' },
  'Lentils (cooked)': { g: 99, unit: '½ cup' },
  'Chickpeas (cooked)': { g: 82, unit: '½ cup' },
  'Banana': { g: 118, unit: 'medium' },
  'Apple': { g: 182, unit: 'medium' },
  'Orange': { g: 131, unit: 'medium' },
  'Blueberries': { g: 148, unit: 'cup' },
  'Strawberries': { g: 152, unit: 'cup' },
  'Avocado': { g: 150, unit: 'avocado' },
  'Grapes': { g: 92, unit: 'cup' },
  'Broccoli': { g: 91, unit: 'cup' },
  'Spinach': { g: 30, unit: 'cup' },
  'Carrot': { g: 61, unit: 'medium' },
  'Bell pepper': { g: 119, unit: 'medium' },
  'Tomato': { g: 123, unit: 'medium' },
  'Cucumber': { g: 104, unit: '½' },
  'Sweet corn': { g: 154, unit: 'cup' },
  'Almonds': { g: 28, unit: 'oz (handful)' },
  'Walnuts': { g: 28, unit: 'oz' },
  'Peanut butter': { g: 32, unit: '2 tbsp' },
  'Olive oil': { g: 14, unit: 'tbsp' },
  'Whole milk': { g: 244, unit: 'cup' },
  'Cheddar cheese': { g: 28, unit: 'oz' },
}

function toResult(seed: WholeFoodSeed): FoodResult {
  const { m } = seed
  const badges: FoodResult['badges'] = [
    { label: 'Whole Food', icon: '🌿', color: 'bg-green-100 text-green-800' },
  ]
  if (m.p >= 15) badges.push({ label: 'High Protein', icon: '💪', color: 'bg-amber-100 text-amber-800' })
  if (m.fib >= 5) badges.push({ label: 'High Fibre', icon: '💚', color: 'bg-teal-100 text-teal-800' })

  // Whole, single-ingredient food: starts high; manual override for calorie-dense items.
  const score = seed.score ?? Math.min(98, 90 + (m.p >= 15 ? 4 : 0) + (m.fib >= 5 ? 4 : 0))

  // Mirror the breakdown shape used for packaged foods so the "why this score"
  // panel reads consistently. Deltas are framed against the same 70 baseline.
  const reasons: FoodResult['reasons'] = [
    { label: 'Single-ingredient whole food', delta: 20 },
  ]
  if (m.p >= 15) reasons.push({ label: 'High in protein', delta: 4 })
  if (m.fib >= 5) reasons.push({ label: 'High in fibre', delta: 4 })
  if (seed.score != null) reasons.push({ label: 'Whole but calorie-dense', delta: seed.score - 90 })

  const sv = SERVING[seed.name]

  return {
    food_name: seed.name,
    brand: null,
    calories: m.kcal,
    protein: m.p,
    carbs: m.c,
    fat: m.f,
    fibre: m.fib,
    score,
    badges,
    flags: [],
    reasons,
    whole: true,
    serving_grams: sv?.g ?? null,
    serving_size: sv?.unit ?? null,
  }
}

const RESULTS = SEED.map(toResult)
const INDEX = SEED.map((s, i) => ({
  result: RESULTS[i],
  terms: [s.name.toLowerCase(), ...(s.aka ?? []).map((a) => a.toLowerCase())],
}))

/** Instant, offline match against the curated whole-food list. */
export function searchWholeFoods(query: string): FoodResult[] {
  const q = query.trim().toLowerCase()
  if (q.length < 2) return []
  const scored = INDEX.map((entry) => {
    let rank = 0
    for (const t of entry.terms) {
      if (t === q) rank = Math.max(rank, 3)
      else if (t.startsWith(q)) rank = Math.max(rank, 2)
      else if (t.includes(q)) rank = Math.max(rank, 1)
    }
    return { result: entry.result, rank }
  })
  return scored
    .filter((s) => s.rank > 0)
    .sort((a, b) => b.rank - a.rank)
    .map((s) => s.result)
}
