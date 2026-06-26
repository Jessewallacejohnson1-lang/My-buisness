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
  location: string | null          // ← add this line
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
    .eq('kind', 'event')
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
    location: e.location ?? null,   // ← add this line
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

// ── Event submission ─────────────────────────────────────────────────────────

export type PostKind = 'event' | 'club' | 'trail' | 'notice'

export type NewPostInput = {
  kind: PostKind
  title: string
  image_url?: string | null
  event_date?: string | null   // Event only (YYYY-MM-DD)
  start_time?: string | null   // Event only, display string e.g. '7pm'
  location?: string | null
  description?: string | null
  cadence?: string | null      // Club only
  length?: string | null       // Trail only
  difficulty?: string | null   // Trail only
}

export type BoardPost = {
  id: string
  kind: PostKind
  title: string
  image_url: string | null
  location: string | null
  description: string | null
  cadence: string | null
  length: string | null
  difficulty: string | null
  status: ClubStatus
  created_at: string
}

/** Upload a post photo to the public `post-images` bucket; returns its public URL. */
export async function uploadPostImage(file: File): Promise<string> {
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) throw new Error('Not signed in')
  const ext = file.name.includes('.') ? file.name.split('.').pop() : 'jpg'
  const path = `${user.id}/${Date.now()}.${ext}`
  const { error } = await supabase.storage.from('post-images').upload(path, file, {
    cacheControl: '3600',
    upsert: false,
  })
  if (error) throw error
  const { data } = supabase.storage.from('post-images').getPublicUrl(path)
  return data.publicUrl
}

/** Insert a post. status defaults to 'approved' (goes live); pass 'pending' for the review queue. */
export async function addPost(input: NewPostInput, status: ClubStatus = 'approved'): Promise<void> {
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) throw new Error('Not signed in')
  const { error } = await supabase.from('club_events').insert({
    kind: input.kind,
    title: input.title,
    image_url: input.image_url ?? null,
    event_date: input.event_date ?? null,
    start_time: input.start_time ?? null,
    location: input.location ?? null,
    description: input.description ?? null,
    cadence: input.cadence ?? null,
    length: input.length ?? null,
    difficulty: input.difficulty ?? null,
    submitted_by: user.id,
    status,
    club_id: null,
  })
  if (error) throw error
}

const BOARD_KINDS = ['club', 'trail', 'notice'] as const

function toBoardPost(e: Record<string, unknown>): BoardPost {
  return {
    id: e.id as string,
    kind: e.kind as PostKind,
    title: e.title as string,
    image_url: (e.image_url as string) ?? null,
    location: (e.location as string) ?? null,
    description: (e.description as string) ?? null,
    cadence: (e.cadence as string) ?? null,
    length: (e.length as string) ?? null,
    difficulty: (e.difficulty as string) ?? null,
    status: e.status as ClubStatus,
    created_at: e.created_at as string,
  }
}

/** Approved Club/Trail/Notice posts for the Board tab, newest first. */
export async function getBoardPosts(): Promise<BoardPost[]> {
  const { data, error } = await supabase
    .from('club_events')
    .select('*')
    .eq('status', 'approved')
    .in('kind', BOARD_KINDS as unknown as string[])
    .order('created_at', { ascending: false })
  if (error) throw error
  return (data ?? []).map(toBoardPost)
}

/** Pending posts awaiting manual admin approval, newest first. */
export async function getPendingPosts(): Promise<BoardPost[]> {
  const { data, error } = await supabase
    .from('club_events')
    .select('*')
    .eq('status', 'pending')
    .order('created_at', { ascending: false })
  if (error) throw error
  return (data ?? []).map(toBoardPost)
}

export async function approvePost(id: string): Promise<void> {
  const { error } = await supabase.from('club_events').update({ status: 'approved' }).eq('id', id)
  if (error) throw error
}

export async function rejectPost(id: string): Promise<void> {
  const { error } = await supabase.from('club_events').update({ status: 'rejected' }).eq('id', id)
  if (error) throw error
}

// ── Calendar helpers ─────────────────────────────────────────────────────────

/** All events on a specific date, with RSVP state. */
export async function getEventsByDate(date: string): Promise<TimelineEvent[]> {
  const uid = await currentUserId()
  const { data: events, error } = await supabase
    .from('club_events')
    .select('*')
    .eq('status', 'approved')
    .eq('kind', 'event')
    .eq('event_date', date)
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
  return (events ?? []).map((e) => ({
    id: e.id,
    title: e.title,
    start_time: e.start_time,
    location: e.location ?? null,
    going_count: counts.get(e.id) ?? 0,
    rsvpd: mine.has(e.id),
    from_joined_club: false,
  }))
}

/** Returns YYYY-MM-DD strings that have at least one approved event in the given month. */
export async function getMonthEventDates(year: number, month: number): Promise<string[]> {
  // month is 1-indexed
  const from = `${year}-${String(month).padStart(2, '0')}-01`
  const lastDay = new Date(year, month, 0).getDate()
  const to = `${year}-${String(month).padStart(2, '0')}-${String(lastDay).padStart(2, '0')}`
  const { data, error } = await supabase
    .from('club_events')
    .select('event_date')
    .eq('status', 'approved')
    .eq('kind', 'event')
    .gte('event_date', from)
    .lte('event_date', to)
  if (error) throw error
  return [...new Set((data ?? []).map((e) => e.event_date))]
}

// ── Quests ───────────────────────────────────────────────────────────────────

export type DailyQuest = {
  id: string
  title: string
  description: string | null
  date: string
}

export async function getTodayQuest(): Promise<DailyQuest | null> {
  const today = localDate()
  const { data, error } = await supabase
    .from('daily_quests')
    .select('id, title, description, date')
    .eq('date', today)
    .maybeSingle()
  if (error) throw error
  return data
}

export async function getQuestCompletionCount(questId: string): Promise<number> {
  const { count, error } = await supabase
    .from('quest_completions')
    .select('*', { count: 'exact', head: true })
    .eq('quest_id', questId)
  if (error) throw error
  return count ?? 0
}

export async function hasUserCompletedQuest(questId: string, userId: string): Promise<boolean> {
  const { data, error } = await supabase
    .from('quest_completions')
    .select('id')
    .eq('quest_id', questId)
    .eq('user_id', userId)
    .maybeSingle()
  if (error) throw error
  return data !== null
}

export async function completeQuest(questId: string): Promise<void> {
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) throw new Error('Not signed in')
  const { error } = await supabase
    .from('quest_completions')
    .insert({ quest_id: questId, user_id: user.id })
  if (error) throw error
}

export async function setQuest(title: string, description: string, date: string): Promise<void> {
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) throw new Error('Not signed in')
  const { error } = await supabase
    .from('daily_quests')
    .upsert({ title, description, date, created_by: user.id }, { onConflict: 'date' })
  if (error) throw error
}
