// rng.ts — tiny deterministic PRNG + helpers. Seeded so a given (user, day) always
// resolves the same pick — reproducible for the once-per-day cache and the verify
// harness. Not cryptographic.

/** 32-bit FNV-1a-style string hash → unsigned int seed. */
export function hashString(s: string): number {
  let h = 2166136261 >>> 0
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i)
    h = Math.imul(h, 16777619)
  }
  return h >>> 0
}

/** mulberry32 PRNG: seed -> function returning floats in [0, 1). */
export function mulberry32(seed: number): () => number {
  let a = seed >>> 0
  return () => {
    a |= 0
    a = (a + 0x6d2b79f5) | 0
    let t = Math.imul(a ^ (a >>> 15), 1 | a)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

/** Deterministic Fisher–Yates shuffle (returns a new array). */
export function seededShuffle<T>(arr: readonly T[], seed: number): T[] {
  const rand = mulberry32(seed)
  const out = arr.slice()
  for (let i = out.length - 1; i > 0; i--) {
    const j = Math.floor(rand() * (i + 1))
    const tmp = out[i]
    out[i] = out[j]
    out[j] = tmp
  }
  return out
}

/** Weighted pick using an already-seeded rand() in [0, 1). */
export function weightedPick<T>(
  items: readonly { item: T; weight: number }[],
  rand: () => number,
): T {
  const total = items.reduce((s, it) => s + it.weight, 0)
  let r = rand() * total
  for (const it of items) {
    r -= it.weight
    if (r < 0) return it.item
  }
  return items[items.length - 1].item
}
