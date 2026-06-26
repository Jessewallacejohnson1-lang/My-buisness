// On-device interests for the welcome onboarding + "Suggested for you".
// Stored in AsyncStorage (per-device, no backend). Matching is plain
// client-side keyword matching against club/trail text the app already loads.
import AsyncStorage from '@react-native-async-storage/async-storage'

export type Interest = { id: string; label: string; keywords: string[] }

export const INTERESTS: Interest[] = [
  { id: 'outdoors', label: 'Outdoors & Trails', keywords: ['hike', 'walk', 'run', 'bike', 'nature', 'park', 'river', 'trail', 'outdoor'] },
  { id: 'music_arts', label: 'Music & Arts', keywords: ['music', 'art', 'choir', 'band', 'craft', 'paint', 'theater', 'sing', 'dance'] },
  { id: 'food', label: 'Food & Drink', keywords: ['food', 'coffee', 'dinner', 'potluck', 'bake', 'brew', 'market', 'meal', 'supper'] },
  { id: 'families', label: 'Families & Kids', keywords: ['kid', 'family', 'parent', 'story', 'playgroup', 'youth', 'child', 'mom', 'dad'] },
  { id: 'faith', label: 'Faith & Fellowship', keywords: ['church', 'faith', 'prayer', 'bible', 'parish', 'worship', 'mass', 'fellowship'] },
  { id: 'sports', label: 'Sports & Fitness', keywords: ['sport', 'fitness', 'yoga', 'gym', 'league', 'ball', 'swim', 'workout', 'pickleball'] },
  { id: 'books', label: 'Books & Learning', keywords: ['book', 'read', 'class', 'learn', 'study', 'library', 'lecture', 'write'] },
  { id: 'service', label: 'Service & Volunteering', keywords: ['volunteer', 'service', 'give', 'clean', 'donate', 'help', 'charity', 'drive'] },
  { id: 'games', label: 'Games & Social', keywords: ['game', 'cards', 'trivia', 'social', 'meetup', 'hang', 'board'] },
]

const INTERESTS_KEY = 'hygge.interests'
const ONBOARDED_KEY = 'hygge.onboarded'

/** Saved interest ids, or [] on first run / read failure. */
export async function getInterests(): Promise<string[]> {
  try {
    const raw = await AsyncStorage.getItem(INTERESTS_KEY)
    return raw ? (JSON.parse(raw) as string[]) : []
  } catch {
    return []
  }
}

export async function setInterests(ids: string[]): Promise<void> {
  try { await AsyncStorage.setItem(INTERESTS_KEY, JSON.stringify(ids)) } catch { /* non-fatal */ }
}

// In-memory mirror of the onboarded flag so the auth gate can read it
// synchronously (avoids a redirect race the moment onboarding finishes).
let onboardedMemo: boolean | null = null

/** Synchronous read of the onboarded flag; null until first async read primes it. */
export function isOnboardedSync(): boolean | null {
  return onboardedMemo
}

/** Whether the welcome flow has been completed (or skipped). Primes the sync memo. */
export async function isOnboarded(): Promise<boolean> {
  if (onboardedMemo !== null) return onboardedMemo
  try { onboardedMemo = (await AsyncStorage.getItem(ONBOARDED_KEY)) === '1' } catch { onboardedMemo = false }
  return onboardedMemo
}

export async function setOnboarded(): Promise<void> {
  onboardedMemo = true
  try { await AsyncStorage.setItem(ONBOARDED_KEY, '1') } catch { /* non-fatal */ }
}

/**
 * Does this item's text match any of the chosen interests?
 * Trails always count toward "Outdoors & Trails".
 */
export function matchesInterests(haystack: string, interestIds: string[], isTrail = false): boolean {
  if (interestIds.length === 0) return false
  if (isTrail && interestIds.includes('outdoors')) return true
  const text = haystack.toLowerCase()
  for (const id of interestIds) {
    const interest = INTERESTS.find((i) => i.id === id)
    if (interest && interest.keywords.some((k) => text.includes(k))) return true
  }
  return false
}
