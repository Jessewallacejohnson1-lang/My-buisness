// "Around town" — real St. Joseph, MN places. This is the single source of truth
// for the carousel and the full-screen place showcase (src/app/place/[slug].tsx).
// Copy is real and true (like the old one-line blurbs); we never invent counts —
// any numbers shown in a showcase come from real event data, never from here.

export type PlaceFact = { label: string; value: string }

export type Place = {
  slug: string // url-safe id used by /place/[slug]
  name: string // display name (matches the old COLLECTIONS.name)
  tagline: string // the one-line card subtitle (was `blurb`)
  image: number // bundled hero photo (reused on card + showcase)
  kw: string[] | null // keywords for matching events to this place
  description: string[] // 1–2 warm, true paragraphs
  facts: PlaceFact[] // a few honest facts (numeric values render in mono)
  where?: string // address/landmark for "Open in Maps"
}

export const PLACES: Place[] = [
  {
    slug: 'downtown',
    name: 'Downtown',
    tagline: 'Shops & cafés on Minnesota St',
    image: require('../../assets/around-town/downtown.jpg'),
    kw: ['downtown', 'minnesota st', 'local blend', 'krewe', 'bo diddley', 'middy', 'college ave', 'bad habit'],
    description: [
      "St. Joe's main street is a few walkable blocks of Minnesota Street — locally-owned coffee, a deli, a brewery taproom, and storefronts where the person behind the counter tends to know your order.",
      "It's the town's living room: slow mornings at the coffeehouse, a summer farmers market, and a steady drift of students and families on foot.",
    ],
    facts: [
      { label: 'Where', value: 'Minnesota Street' },
      { label: 'Coffee', value: 'The Local Blend' },
      { label: 'Pint', value: 'Bad Habit Brewing' },
    ],
    where: 'Minnesota Street, St. Joseph, MN',
  },
  {
    slug: 'saint-bens',
    name: "Saint Ben's",
    tagline: 'College of Saint Benedict',
    image: require('../../assets/around-town/saint-bens.jpg'),
    kw: ['saint ben', 'st. ben', 'st ben', 'csb', 'benedict', 'gorecki', 'campus'],
    description: [
      "The College of Saint Benedict — 'St. Ben's' — is a Benedictine women's liberal-arts college on the north edge of town, partnered with Saint John's across the river.",
      'Tree-lined paths, the Gorecki center, and a hospitality you can feel the moment you step onto campus. Concerts, lectures, and games here are open to neighbors.',
    ],
    facts: [
      { label: 'Founded', value: '1887' },
      { label: 'Type', value: "Women's liberal arts" },
      { label: 'Partner', value: "Saint John's" },
    ],
    where: 'College of Saint Benedict, St. Joseph, MN',
  },
  {
    slug: 'sacred-heart-chapel',
    name: 'Sacred Heart Chapel',
    tagline: 'The monastery & its dome',
    image: require('../../assets/around-town/sacred-heart-chapel.jpg'),
    kw: ['chapel', 'sacred heart', 'monastery', 'mass', 'sisters'],
    description: [
      'At the heart of Saint Benedict’s Monastery stands the Sacred Heart Chapel, its copper dome a landmark you can spot from the highway.',
      'Home to the Benedictine sisters who founded both the monastery and the college, it’s a quiet, candle-warmed space open for prayer and song.',
    ],
    facts: [
      { label: 'Feature', value: 'Copper dome' },
      { label: 'Home to', value: 'Benedictine sisters' },
      { label: 'Open for', value: 'Prayer & song' },
    ],
    where: 'Sacred Heart Chapel, St. Joseph, MN',
  },
  {
    slug: 'saint-johns',
    name: "Saint John's",
    tagline: 'The Abbey in Collegeville',
    image: require('../../assets/around-town/saint-johns-abbey.jpg'),
    kw: ['saint john', 'st. john', 'st john', 'sju', 'abbey', 'collegeville'],
    description: [
      'Just west in Collegeville, Saint John’s Abbey and University sit among thousands of acres of woods, prairie, and lake.',
      'The Abbey Church — Marcel Breuer’s soaring concrete bell banner — draws architecture lovers, and the arboretum trails and Stella Maris chapel are open to wander.',
    ],
    facts: [
      { label: 'Where', value: 'Collegeville' },
      { label: 'Architect', value: 'Marcel Breuer' },
      { label: 'Grounds', value: '2,700 acres' },
    ],
    where: "Saint John's Abbey, Collegeville, MN",
  },
  {
    slug: 'wobegon-trail',
    name: 'Wobegon Trail',
    tagline: 'Bike, walk & run the trail',
    image: require('../../assets/around-town/wobegon-trail.jpg'),
    kw: ['wobegon', 'trail', 'bike', 'walk', 'run', 'ride', 'river', 'watab'],
    description: [
      'The Lake Wobegon Trail runs right through town — a flat, paved rail-trail named for Garrison Keillor’s fictional hometown.',
      'Bike it, run it, walk the dog, or push a stroller; it links St. Joseph toward St. Cloud one way and rolls out past Avon and Albany the other.',
    ],
    facts: [
      { label: 'Surface', value: 'Paved rail-trail' },
      { label: 'Named for', value: "Keillor's Lake Wobegon" },
      { label: 'Good for', value: 'Bikes, runs, strollers' },
    ],
    where: 'Lake Wobegon Trail, St. Joseph, MN',
  },
]

export function placeBySlug(slug: string): Place | null {
  return PLACES.find((p) => p.slug === slug) ?? null
}

// Back-compat: the carousel and event-filter still consume the old `Collection`
// shape. Keep them working by projecting PLACES — no other call sites change.
export type Collection = { name: string; blurb: string; image: number; kw: string[] | null }
export const COLLECTIONS: Collection[] = PLACES.map((p) => ({
  name: p.name,
  blurb: p.tagline,
  image: p.image,
  kw: p.kw,
}))

export function matchesKw(text: string, kw: string[] | null): boolean {
  if (!kw) return true
  const t = text.toLowerCase()
  return kw.some((k) => t.includes(k))
}
