import { createClient } from './supabase/client'
import { localDate } from './db'

const supabase = createClient()

export const ADMIN_EMAIL =
  process.env.NEXT_PUBLIC_ADMIN_EMAIL ?? 'jessewallacejohnson1@icloud.com'

export function isAdminEmail(email?: string | null): boolean {
  return !!email && email.toLowerCase() === ADMIN_EMAIL.toLowerCase()
}

/** Best-effort first name from an email local-part; null when it isn't clean. */
export function firstNameFromEmail(email?: string | null): string | null {
  if (!email) return null
  const local = email.split('@')[0].replace(/\d+$/, '')
  const token = local.split(/[._-]/)[0]
  if (!token || token.length > 12) return null
  return token.charAt(0).toUpperCase() + token.slice(1)
}

export type ClubStatus = 'pending' | 'approved' | 'rejected'

export type ClubRow = {
  id: string
  submitted_by: string | null
  status: ClubStatus
  name: string
  host: string | null
  schedule: string | null
  vibe: string | null
  created_at: string
}

/** A club plus the viewer-relative bits the UI needs. */
export type ClubView = ClubRow & { member_count: number; joined: boolean }

export type ClubInput = {
  name: string
  host?: string
  schedule?: string
  vibe?: string
}

/** One timeline row: a club event with the viewer's RSVP state + going count. */
export type TimelineEvent = {
  id: string
  title: string
  start_time: string | null
  going_count: number
  rsvpd: boolean
  /** event belongs to a club the viewer has joined — drives the "for you" vs count display */
  from_joined_club: boolean
}

export type WeekEvent = {
  id: string
  title: string
  date_label: string   // "Sat"
  going_count: number
}

async function currentUserId(): Promise<string | null> {
  const { data: { user } } = await supabase.auth.getUser()
  return user?.id ?? null
}

/** The signed-in user's id + email, or null. Uses the module-scoped client. */
export async function getCurrentUser(): Promise<{ id: string; email: string | null } | null> {
  const { data: { user } } = await supabase.auth.getUser()
  return user ? { id: user.id, email: user.email ?? null } : null
}

// ── Clubs ────────────────────────────────────────────────────────────────────

export async function getApprovedClubs(): Promise<ClubView[]> {
  const uid = await currentUserId()
  const { data: clubs, error } = await supabase
    .from('clubs')
    .select('*')
    .eq('status', 'approved')
    .order('created_at', { ascending: true })
  if (error) throw error
  const ids = (clubs ?? []).map((c) => c.id)
  const counts = new Map<string, number>()
  const mine = new Set<string>()
  if (ids.length) {
    const { data: members } = await supabase
      .from('club_members')
      .select('club_id, user_id')
      .in('club_id', ids)
    ;(members ?? []).forEach((m) => {
      counts.set(m.club_id, (counts.get(m.club_id) ?? 0) + 1)
      if (uid && m.user_id === uid) mine.add(m.club_id)
    })
  }
  return (clubs ?? []).map((c) => ({
    ...c,
    member_count: counts.get(c.id) ?? 0,
    joined: mine.has(c.id),
  }))
}

export async function getPendingClubs(): Promise<ClubRow[]> {
  const { data, error } = await supabase
    .from('clubs')
    .select('*')
    .eq('status', 'pending')
    .order('created_at', { ascending: true })
  if (error) throw error
  return data ?? []
}

export async function joinClub(clubId: string): Promise<void> {
  const uid = await currentUserId()
  if (!uid) throw new Error('Not signed in')
  const { error } = await supabase
    .from('club_members')
    .upsert({ club_id: clubId, user_id: uid }, { onConflict: 'club_id,user_id' })
  if (error) throw error
}

export async function leaveClub(clubId: string): Promise<void> {
  const uid = await currentUserId()
  if (!uid) throw new Error('Not signed in')
  const { error } = await supabase
    .from('club_members')
    .delete()
    .eq('club_id', clubId)
    .eq('user_id', uid)
  if (error) throw error
}

export async function submitClub(input: ClubInput): Promise<ClubRow> {
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) throw new Error('Not signed in')
  const status: ClubStatus = isAdminEmail(user.email) ? 'approved' : 'pending'
  const { data, error } = await supabase
    .from('clubs')
    .insert({ ...input, submitted_by: user.id, status })
    .select()
    .single()
  if (error) throw error
  return data
}

export async function setClubStatus(id: string, status: ClubStatus): Promise<void> {
  const { error } = await supabase.from('clubs').update({ status }).eq('id', id)
  if (error) throw error
}

// ── Timeline / events ────────────────────────────────────────────────────────

export async function getTodayEvents(): Promise<TimelineEvent[]> {
  const uid = await currentUserId()
  const today = localDate()
  const { data: events, error } = await supabase
    .from('club_events')
    .select('*')
    .eq('status', 'approved')
    .eq('event_date', today)
    .order('start_time', { ascending: true })
  if (error) throw error
  const ids = (events ?? []).map((e) => e.id)
  const counts = new Map<string, number>()
  const mine = new Set<string>()
  if (ids.length) {
    const { data: rsvps } = await supabase
      .from('event_rsvps')
      .select('event_id, user_id')
      .in('event_id', ids)
    ;(rsvps ?? []).forEach((r) => {
      counts.set(r.event_id, (counts.get(r.event_id) ?? 0) + 1)
      if (uid && r.user_id === uid) mine.add(r.event_id)
    })
  }
  const joinedClubs = new Set<string>()
  if (uid) {
    const { data: mem } = await supabase
      .from('club_members')
      .select('club_id')
      .eq('user_id', uid)
    ;(mem ?? []).forEach((m) => joinedClubs.add(m.club_id))
  }
  return (events ?? []).map((e) => ({
    id: e.id,
    title: e.title,
    start_time: e.start_time,
    going_count: counts.get(e.id) ?? 0,
    rsvpd: mine.has(e.id),
    from_joined_club: e.club_id ? joinedClubs.has(e.club_id) : false,
  }))
}

export async function getWeekEvents(): Promise<WeekEvent[]> {
  const today = localDate()
  const until = localDate(addDays(7))
  const { data: events, error } = await supabase
    .from('club_events')
    .select('*')
    .eq('status', 'approved')
    .gt('event_date', today)
    .lte('event_date', until)
    .order('event_date', { ascending: true })
  if (error) throw error
  const ids = (events ?? []).map((e) => e.id)
  const counts = new Map<string, number>()
  if (ids.length) {
    const { data: rsvps } = await supabase
      .from('event_rsvps')
      .select('event_id')
      .in('event_id', ids)
    ;(rsvps ?? []).forEach((r) => counts.set(r.event_id, (counts.get(r.event_id) ?? 0) + 1))
  }
  return (events ?? []).map((e) => ({
    id: e.id,
    title: e.title,
    date_label: weekdayLabel(e.event_date),
    going_count: counts.get(e.id) ?? 0,
  }))
}

export async function rsvpEvent(eventId: string): Promise<void> {
  const uid = await currentUserId()
  if (!uid) throw new Error('Not signed in')
  const { error } = await supabase
    .from('event_rsvps')
    .upsert({ event_id: eventId, user_id: uid }, { onConflict: 'event_id,user_id' })
  if (error) throw error
}

export async function unRsvpEvent(eventId: string): Promise<void> {
  const uid = await currentUserId()
  if (!uid) throw new Error('Not signed in')
  const { error } = await supabase
    .from('event_rsvps')
    .delete()
    .eq('event_id', eventId)
    .eq('user_id', uid)
  if (error) throw error
}

// ── small date helpers (local-tz, never UTC) ─────────────────────────────────

function addDays(n: number): Date {
  const d = new Date()
  d.setDate(d.getDate() + n)
  return d
}

/** "Sat" from a YYYY-MM-DD string, parsed in local time. */
function weekdayLabel(ymd: string): string {
  const [y, m, d] = ymd.split('-').map(Number)
  return new Date(y, m - 1, d).toLocaleDateString('en-US', { weekday: 'short' })
}
