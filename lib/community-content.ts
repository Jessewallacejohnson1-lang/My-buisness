/**
 * Seed content for the Community tier — the editorial / ambient pieces that
 * aren't yet DB-backed (Sunday Letter, Daily Hello, quests, advice, weather).
 * Swap any of these for a real table/API later without touching the UI.
 */

export const WEATHER = {
  morning: 'St. Joe is 47° and clear.',
  evening: 'The moon is full tonight. Sky is clear.',
}

export const MORNING = {
  quest: 'Compliment a stranger today.',
  questCta: 'Tap to be a Hygger',
  questDone: "✦ You're a Hygger today.",
  advice:
    'Morning sunlight within 30 minutes of waking helps set your sleep rhythm tonight. Even overcast light counts — step outside for a few minutes.',
}

export const EVENING = {
  quest: 'Notice three things on your walk you usually miss.',
  windDown: 'Make a cup of chamomile tea. Read for 20 minutes before bed.',
}

export const SUNDAY_LETTER = {
  eyebrow: 'Sunday Letter',
  headline: 'A good week to go slower.',
  byline: 'June 15 · Jesse V.',
  paragraphs: [
    "St. Joe had its first real summer week this year. I noticed people on the trails earlier than usual — 6am joggers, kids on bikes by the river. Something about warm mornings makes the town feel like it's already ahead of itself.",
    'This week: Trivia is Thursday. Run Club added a new route along the south trail — Marcus says it adds about 8 minutes. Farmers market is Saturday, 8am–noon. Come say hi if you see me there.',
  ],
  signoff: '— Jesse',
}

export const DAILY_HELLO = {
  initial: 'M',
  name: 'Marcus T.',
  bio: 'Runs on weekends. Into cold plunge and Trivia Night.',
  quote: 'Trying to make every Trivia Night this year.',
}
