export type FoodResult = {
  food_name: string
  brand: string | null
  calories: number
  protein: number
  carbs: number
  fat: number
  fibre: number
  score: number
  badges: { label: string; icon: string; color: string }[]
  flags: string[]
  image?: string | null
}

/** Picks exactly the food_logs columns — strips display-only fields like image. */
export function toLogEntry(
  food: FoodResult,
  meal: 'Breakfast' | 'Lunch' | 'Dinner' | 'Snacks',
  date: string
) {
  const { food_name, brand, calories, protein, carbs, fat, fibre, score, badges, flags } = food
  return { food_name, brand, calories, protein, carbs, fat, fibre, score, badges, flags, meal, date }
}

function computeScore(product: Record<string, unknown>): { score: number; badges: FoodResult['badges']; flags: string[] } {
  let score = 70
  const badges: FoodResult['badges'] = []
  const flags: string[] = []

  const nova = product.nova_group as number | undefined
  if (nova === 1) { score += 20; badges.push({ label: 'Whole Food', icon: '🌿', color: 'bg-green-100 text-green-800' }) }
  else if (nova === 2) score += 10
  else if (nova === 3) score -= 10
  else if (nova === 4) { score -= 25; flags.push('Ultra-processed food (NOVA group 4)') }

  const nutriscore = (product.nutriscore_grade as string | undefined)?.toLowerCase()
  if (nutriscore === 'a') score += 15
  else if (nutriscore === 'b') score += 8
  else if (nutriscore === 'd') score -= 10
  else if (nutriscore === 'e') score -= 20

  const additives = (product.additives_tags as string[] | undefined) ?? []
  if (additives.length === 0) { score += 10; badges.push({ label: 'No Additives', icon: '✓', color: 'bg-emerald-100 text-emerald-800' }) }
  else if (additives.length > 5) { score -= 15; flags.push(`Contains ${additives.length} additives`) }

  const labels = ((product.labels_tags as string[] | undefined) ?? []).join(' ')
  if (labels.includes('organic')) { score += 8; badges.push({ label: 'Organic', icon: '🌿', color: 'bg-green-100 text-green-800' }) }
  if (labels.includes('non-gmo') || labels.includes('no-gmo')) badges.push({ label: 'Non-GMO', icon: '✓', color: 'bg-emerald-100 text-emerald-800' })
  if (labels.includes('gluten-free')) badges.push({ label: 'Gluten Free', icon: '🌾', color: 'bg-yellow-100 text-yellow-800' })
  if (labels.includes('vegan')) badges.push({ label: 'Vegan', icon: '🌱', color: 'bg-green-100 text-green-800' })

  const packaging = ((product.packaging_tags as string[] | undefined) ?? []).join(' ')
  if (packaging.includes('plastic')) flags.push('Packaged in plastic — microplastic risk')

  const ingredients = ((product.ingredients_text as string | undefined) ?? '').toLowerCase()
  if (ingredients.includes('aspartame') || ingredients.includes('sucralose') || ingredients.includes('saccharin')) {
    flags.push('Contains artificial sweeteners — linked to gut microbiome disruption')
    score -= 15
  }
  if (ingredients.includes('high fructose') || ingredients.includes('corn syrup')) {
    flags.push('Contains high fructose corn syrup')
    score -= 10
  }
  if (/red\s*4[05]|yellow\s*[56]|blue\s*[12]/.test(ingredients)) {
    flags.push('Contains artificial dyes')
    score -= 10
  }

  const nutriments = (product.nutriments as Record<string, number> | undefined) ?? {}
  const fibre = nutriments['fiber_100g'] ?? 0
  if (fibre > 5) badges.push({ label: 'High Fibre', icon: '💚', color: 'bg-teal-100 text-teal-800' })
  const protein = nutriments['proteins_100g'] ?? 0
  if (protein > 15) badges.push({ label: 'High Protein', icon: '💪', color: 'bg-amber-100 text-amber-800' })

  return { score: Math.max(1, Math.min(100, score)), badges, flags }
}

export async function searchFood(query: string): Promise<FoodResult[]> {
  const res = await fetch(
    `https://world.openfoodfacts.org/cgi/search.pl?search_terms=${encodeURIComponent(query)}&json=1&page_size=10&fields=product_name,brands,nutriments,nova_group,nutriscore_grade,additives_tags,labels_tags,packaging_tags,ingredients_text`
  )
  const json = await res.json()
  const products = (json.products ?? []) as Record<string, unknown>[]
  return products
    .filter(p => p.product_name)
    .map(p => {
      const n = (p.nutriments as Record<string, number>) ?? {}
      const { score, badges, flags } = computeScore(p)
      return {
        food_name: p.product_name as string,
        brand: (p.brands as string | undefined) ?? null,
        calories: Math.round(n['energy-kcal_100g'] ?? n['energy-kcal'] ?? 0),
        protein: Math.round((n['proteins_100g'] ?? 0) * 10) / 10,
        carbs: Math.round((n['carbohydrates_100g'] ?? 0) * 10) / 10,
        fat: Math.round((n['fat_100g'] ?? 0) * 10) / 10,
        fibre: Math.round((n['fiber_100g'] ?? 0) * 10) / 10,
        score,
        badges,
        flags,
      }
    })
}

export async function lookupBarcode(barcode: string): Promise<FoodResult | null> {
  const res = await fetch(`https://world.openfoodfacts.org/api/v0/product/${barcode}.json`)
  const json = await res.json()
  if (json.status !== 1 || !json.product) return null
  const p = json.product as Record<string, unknown>
  const n = (p.nutriments as Record<string, number>) ?? {}
  const { score, badges, flags } = computeScore(p)
  return {
    food_name: (p.product_name as string | undefined) ?? 'Unknown product',
    brand: (p.brands as string | undefined)?.split(',')[0]?.trim() ?? null,
    calories: Math.round(n['energy-kcal_100g'] ?? n['energy-kcal'] ?? 0),
    protein: Math.round((n['proteins_100g'] ?? 0) * 10) / 10,
    carbs: Math.round((n['carbohydrates_100g'] ?? 0) * 10) / 10,
    fat: Math.round((n['fat_100g'] ?? 0) * 10) / 10,
    fibre: Math.round((n['fiber_100g'] ?? 0) * 10) / 10,
    score,
    badges,
    flags,
    image: (p.image_front_url as string | undefined) ?? (p.image_url as string | undefined) ?? null,
  }
}
