import type { SupabaseClient } from '@supabase/supabase-js'
import { localDate, addDays, weekdayLabel } from './db'
import type {
  ClubInput, ClubRow, ClubStatus, ClubView,
  DailyQuest, NewEventInput, TimelineEvent, WeekEvent,
} from './types'

export const DEFAULT_ADMIN_EMAIL = 'jessewallacejohnson1@icloud.com'

export function isAdminEmail(email?: string | null, adminEmail = DEFAULT_ADMIN_EMAIL): boolean {
  return !!email && email.toLowerCase() === adminEmail.toLowerCase()
}

/** Best-effort first name from an email local-part; null when it isn't clean. */
export function firstNameFromEmail(email?: string | null): string | null {
  if (!email) return null
  const local = email.split('@')[0].replace(/\d+$/, '')
  const token = local.split(/[._-]/)[0]
  if (!token || token.length > 12) return null
  return token.charAt(0).toUpperCase() + token.slice(1)
}

/**
 * All community DB helpers, bound to a Supabase client. Each app (web, mobile)
 * creates its own client (cookies on web, SecureStore/AsyncStorage on mobile)
 * and passes it here, so the queries stay identical across platforms.
 */
export function createCommunityApi(supabase: SupabaseClient, adminEmail = DEFAULT_ADMIN_EMAIL) {
  async function currentUserId(): Promise<string | null> {
    const { data: { user } } = await supabase.auth.getUser()
    return user?.id ?? null
  }

  async function getCurrentUser(): Promise<{ id: string; email: string | null } | null> {
    const { data: { user } } = await supabase.auth.getUser()
    return user ? { id: user.id, email: user.email ?? null } : null
  }

  // ── Clubs ──────────────────────────────────────────────────────────────────
  async function getApprovedClubs(): Promise<ClubView[]> {
    const uid = await currentUserId()
    const { data: clubs, error } = await supabase
      .from('clubs').select('*').eq('status', 'approved').order('created_at', { ascending: true })
    if (error) throw error
    const ids = (clubs ?? []).map((c) => c.id)
    const counts = new Map<string, number>()
    const mine = new Set<string>()
    if (ids.length) {
      const { data: members } = await supabase.from('club_members').select('club_id, user_id').in('club_id', ids)
      ;(members ?? []).forEach((m) => {
        counts.set(m.club_id, (counts.get(m.club_id) ?? 0) + 1)
        if (uid && m.user_id === uid) mine.add(m.club_id)
      })
    }
    return (clubs ?? []).map((c) => ({ ...c, member_count: counts.get(c.id) ?? 0, joined: mine.has(c.id) }))
  }

  async function joinClub(clubId: string): Promise<void> {
    const uid = await currentUserId()
    if (!uid) throw new Error('Not signed in')
    const { error } = await supabase.from('club_members').upsert({ club_id: clubId, user_id: uid }, { onConflict: 'club_id,user_id' })
    if (error) throw error
  }

  async function leaveClub(clubId: string): Promise<void> {
    const uid = await currentUserId()
    if (!uid) throw new Error('Not signed in')
    const { error } = await supabase.from('club_members').delete().eq('club_id', clubId).eq('user_id', uid)
    if (error) throw error
  }

  async function submitClub(input: ClubInput): Promise<ClubRow> {
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) throw new Error('Not signed in')
    const status: ClubStatus = isAdminEmail(user.email, adminEmail) ? 'approved' : 'pending'
    const { data, error } = await supabase.from('clubs').insert({ ...input, submitted_by: user.id, status }).select().single()
    if (error) throw error
    return data
  }

  // ── Timeline / events ────────────────────────────────────────────────────────
  async function getTodayEvents(): Promise<TimelineEvent[]> {
    const uid = await currentUserId()
    const today = localDate()
    const { data: events, error } = await supabase
      .from('club_events').select('*').eq('status', 'approved').eq('event_date', today).order('start_time', { ascending: true })
    if (error) throw error
    const ids = (events ?? []).map((e) => e.id)
    const counts = new Map<string, number>()
    const mine = new Set<string>()
    if (ids.length) {
      const { data: rsvps } = await supabase.from('event_rsvps').select('event_id, user_id').in('event_id', ids)
      ;(rsvps ?? []).forEach((r) => {
        counts.set(r.event_id, (counts.get(r.event_id) ?? 0) + 1)
        if (uid && r.user_id === uid) mine.add(r.event_id)
      })
    }
    const joinedClubs = new Set<string>()
    if (uid) {
      const { data: mem } = await supabase.from('club_members').select('club_id').eq('user_id', uid)
      ;(mem ?? []).forEach((m) => joinedClubs.add(m.club_id))
    }
    return (events ?? []).map((e) => ({
      id: e.id, title: e.title, start_time: e.start_time, location: e.location ?? null,
      going_count: counts.get(e.id) ?? 0, rsvpd: mine.has(e.id),
      from_joined_club: e.club_id ? joinedClubs.has(e.club_id) : false,
    }))
  }

  async function getWeekEvents(): Promise<WeekEvent[]> {
    const today = localDate()
    const until = localDate(addDays(7))
    const { data: events, error } = await supabase
      .from('club_events').select('*').eq('status', 'approved').gt('event_date', today).lte('event_date', until).order('event_date', { ascending: true })
    if (error) throw error
    const ids = (events ?? []).map((e) => e.id)
    const counts = new Map<string, number>()
    if (ids.length) {
      const { data: rsvps } = await supabase.from('event_rsvps').select('event_id').in('event_id', ids)
      ;(rsvps ?? []).forEach((r) => counts.set(r.event_id, (counts.get(r.event_id) ?? 0) + 1))
    }
    return (events ?? []).map((e) => ({ id: e.id, title: e.title, date_label: weekdayLabel(e.event_date), going_count: counts.get(e.id) ?? 0 }))
  }

  async function rsvpEvent(eventId: string): Promise<void> {
    const uid = await currentUserId()
    if (!uid) throw new Error('Not signed in')
    const { error } = await supabase.from('event_rsvps').upsert({ event_id: eventId, user_id: uid }, { onConflict: 'event_id,user_id' })
    if (error) throw error
  }

  async function unRsvpEvent(eventId: string): Promise<void> {
    const uid = await currentUserId()
    if (!uid) throw new Error('Not signed in')
    const { error } = await supabase.from('event_rsvps').delete().eq('event_id', eventId).eq('user_id', uid)
    if (error) throw error
  }

  async function addEvent(input: NewEventInput): Promise<void> {
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) throw new Error('Not signed in')
    const base = { ...input, submitted_by: user.id, status: 'approved', club_id: null }
    const { error } = await supabase.from('club_events').insert(base)
    // If the image_url column hasn't been added yet (migration-event-images.sql),
    // retry once without it so the event still posts.
    if (error && input.image_url && /image_url/.test(error.message)) {
      const { image_url, ...withoutImage } = base
      void image_url
      const retry = await supabase.from('club_events').insert(withoutImage)
      if (retry.error) throw retry.error
      return
    }
    if (error) throw error
  }

  // ── Calendar ──────────────────────────────────────────────────────────────
  async function getEventsByDate(date: string): Promise<TimelineEvent[]> {
    const uid = await currentUserId()
    const { data: events, error } = await supabase
      .from('club_events').select('*').eq('status', 'approved').eq('event_date', date).order('start_time', { ascending: true })
    if (error) throw error
    const ids = (events ?? []).map((e) => e.id)
    const counts = new Map<string, number>()
    const mine = new Set<string>()
    if (ids.length) {
      const { data: rsvps } = await supabase.from('event_rsvps').select('event_id, user_id').in('event_id', ids)
      ;(rsvps ?? []).forEach((r) => {
        counts.set(r.event_id, (counts.get(r.event_id) ?? 0) + 1)
        if (uid && r.user_id === uid) mine.add(r.event_id)
      })
    }
    return (events ?? []).map((e) => ({
      id: e.id, title: e.title, start_time: e.start_time, location: e.location ?? null,
      going_count: counts.get(e.id) ?? 0, rsvpd: mine.has(e.id), from_joined_club: false,
    }))
  }

  async function getMonthEventDates(year: number, month: number): Promise<string[]> {
    const from = `${year}-${String(month).padStart(2, '0')}-01`
    const lastDay = new Date(year, month, 0).getDate()
    const to = `${year}-${String(month).padStart(2, '0')}-${String(lastDay).padStart(2, '0')}`
    const { data, error } = await supabase
      .from('club_events').select('event_date').eq('status', 'approved').gte('event_date', from).lte('event_date', to)
    if (error) throw error
    return [...new Set((data ?? []).map((e) => e.event_date))]
  }

  // ── Quests ──────────────────────────────────────────────────────────────────
  async function getTodayQuest(): Promise<DailyQuest | null> {
    const today = localDate()
    const { data, error } = await supabase.from('daily_quests').select('id, title, description, date').eq('date', today).maybeSingle()
    if (error) throw error
    return data
  }

  async function getQuestCompletionCount(questId: string): Promise<number> {
    const { count, error } = await supabase.from('quest_completions').select('*', { count: 'exact', head: true }).eq('quest_id', questId)
    if (error) throw error
    return count ?? 0
  }

  async function hasUserCompletedQuest(questId: string, userId: string): Promise<boolean> {
    const { data, error } = await supabase.from('quest_completions').select('id').eq('quest_id', questId).eq('user_id', userId).maybeSingle()
    if (error) throw error
    return data !== null
  }

  async function completeQuest(questId: string): Promise<void> {
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) throw new Error('Not signed in')
    const { error } = await supabase.from('quest_completions').insert({ quest_id: questId, user_id: user.id })
    if (error) throw error
  }

  async function setQuest(title: string, description: string, date: string): Promise<void> {
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) throw new Error('Not signed in')
    const { error } = await supabase.from('daily_quests').upsert({ title, description, date, created_by: user.id }, { onConflict: 'date' })
    if (error) throw error
  }

  return {
    currentUserId, getCurrentUser,
    getApprovedClubs, joinClub, leaveClub, submitClub,
    getTodayEvents, getWeekEvents, rsvpEvent, unRsvpEvent, addEvent,
    getEventsByDate, getMonthEventDates,
    getTodayQuest, getQuestCompletionCount, hasUserCompletedQuest, completeQuest, setQuest,
  }
}

export type CommunityApi = ReturnType<typeof createCommunityApi>
