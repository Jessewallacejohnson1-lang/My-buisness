// Shared domain types for the Hygge community app (web + mobile).

export type ClubStatus = 'pending' | 'approved' | 'rejected'

export type ClubRow = {
  id: string
  submitted_by: string | null
  status: ClubStatus
  name: string
  host: string | null
  schedule: string | null        // when — "Every Saturday, 7am"
  location: string | null        // where — "Millstream Park"
  vibe: string | null            // short one-liner
  description: string | null     // the longer "about"
  expectations: string | null    // what to expect / bring
  created_at: string
}

export type ClubView = ClubRow & { member_count: number; joined: boolean }

export type ClubInput = {
  name: string
  host?: string
  schedule?: string
  location?: string
  vibe?: string
  description?: string
  expectations?: string
}

/** One timeline row: a club event with the viewer's RSVP state + going count. */
export type TimelineEvent = {
  id: string
  title: string
  start_time: string | null
  location: string | null
  going_count: number
  rsvpd: boolean
  /** name of the club this event belongs to, or null for a plain town event */
  club_name: string | null
  /** event belongs to a club the viewer has joined */
  from_joined_club: boolean
}

export type WeekEvent = {
  id: string
  title: string
  date_label: string // "Sat"
  going_count: number
}

/** Lightweight event for the calendar's expanded-week agenda (grouped by date). */
export type AgendaEvent = {
  id: string
  title: string
  event_date: string // YYYY-MM-DD
  start_time: string | null
  location: string | null
}

/** A future event for the Activities browse list. */
export type UpcomingEvent = {
  id: string
  title: string
  event_date: string   // YYYY-MM-DD
  start_time: string | null
  location: string | null
  going_count: number
  created_at: string
}

/**
 * Event category taxonomy — the shared vocabulary for `club_events.category`
 * (needs migration-event-category.sql). Mirrors the INTERESTS ids in
 * apps/mobile/src/lib/interests.ts so category and interest matching share one
 * list, and keeps the native iOS twin (EventCategory enum) in sync. Stored as
 * free text; a null / legacy / unknown value is treated as 'other'.
 */
export type EventCategory =
  | 'outdoors'
  | 'music_arts'
  | 'food'
  | 'families'
  | 'faith'
  | 'sports'
  | 'books'
  | 'service'
  | 'games'
  | 'other'

export const EVENT_CATEGORIES: readonly EventCategory[] = [
  'outdoors', 'music_arts', 'food', 'families', 'faith',
  'sports', 'books', 'service', 'games', 'other',
]

export type NewEventInput = {
  title: string
  event_date: string // YYYY-MM-DD
  start_time: string // display string e.g. '7pm'
  location: string
  description?: string
  image_url?: string // optional event image (needs migration-event-images.sql)
  category?: EventCategory // optional event category (needs migration-event-category.sql)
}

export type PostKind = 'event' | 'trail'

export type NewTrailInput = {
  title: string
  location: string
  length?: string
  difficulty?: string
  description?: string
  image_url?: string
}

export type Trail = {
  id: string
  title: string
  location: string | null
  length: string | null
  difficulty: string | null
  description: string | null
  image_url: string | null
  status: ClubStatus
  created_at: string
}

export type PendingPost = Trail & {
  kind: PostKind
  event_date: string | null
  start_time: string | null
}

export type DailyQuest = {
  id: string
  title: string
  description: string | null
  date: string
}
