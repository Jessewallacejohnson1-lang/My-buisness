// datasource.ts — per-user Almanac reads over Supabase PostgREST.
//
// PRIVACY: every read here is an IN-APP action the user took — their RSVPs
// (event_rsvps), the town's posts, and the user's own almanac history. No device
// location, nothing the user didn't do inside the app.
//
// The interface is injectable so the context builder can be exercised with fake data
// in the local demo / variety-verify harness (no live Supabase secrets needed).

export interface UpcomingEvent {
  title: string
  event_date: string // YYYY-MM-DD
  start_time: string | null
  location: string | null
  going_count: number
}

export interface AttendedEvent {
  title: string
  event_date: string
  location: string | null
  /** True when another event of the same title exists on a different date (it recurs). */
  recurs: boolean
}

export interface NewestEvent {
  title: string
  going_count: number
}

export interface HistoryRow {
  body_text: string
  places_mentioned: string[]
  date: string
  format_used: string | null
}

export interface DataSource {
  /** Approved events the user RSVP'd to, from today through `endISO` (inclusive). */
  upcomingEvents(userId: string, todayISO: string, endISO: string): Promise<UpcomingEvent[]>
  /** The user's most recent PAST attended (RSVP'd) event, or null. */
  lastAttendedEvent(userId: string, todayISO: string): Promise<AttendedEvent | null>
  /** Count of new approved events since `sinceISO` (a timestamptz). */
  newPostCount24h(sinceISO: string): Promise<number>
  /** The newest approved event town-wide, with its going count. */
  newestEvent(): Promise<NewestEvent | null>
  /** The user's last `limit` almanac rows, newest first. */
  recentHistory(userId: string, limit: number): Promise<HistoryRow[]>
}

type Rest = (path: string, init?: RequestInit) => Promise<Response>

/** Build a PostgREST caller bound to the project URL + service-role key. */
export function makeRest(supaUrl: string, serviceKey: string, fetchImpl: typeof fetch = fetch): Rest {
  return (path, init) =>
    fetchImpl(`${supaUrl}/rest/v1/${path}`, {
      ...init,
      headers: {
        apikey: serviceKey,
        Authorization: `Bearer ${serviceKey}`,
        "Content-Type": "application/json",
        ...(init?.headers ?? {}),
      },
    })
}

/** The real DataSource, reading club_events / event_rsvps / almanac_daily via PostgREST. */
export function postgrestDataSource(rest: Rest): DataSource {
  return {
    async upcomingEvents(userId, todayISO, endISO) {
      const ids = await myRsvpEventIds(rest, userId)
      if (ids.length === 0) return []
      const rows = await getJson(
        rest,
        `club_events?select=id,title,event_date,start_time,location` +
          `&id=in.(${ids.join(",")})&status=eq.approved&kind=eq.event` +
          `&event_date=gte.${todayISO}&event_date=lte.${endISO}&order=event_date.asc`,
      )
      const counts = await goingCounts(rest, rows.map((r: any) => r.id))
      return rows.map((r: any) => ({
        title: r.title,
        event_date: r.event_date,
        start_time: r.start_time ?? null,
        location: r.location ?? null,
        going_count: counts.get(r.id) ?? 0,
      }))
    },

    async lastAttendedEvent(userId, todayISO) {
      const ids = await myRsvpEventIds(rest, userId)
      if (ids.length === 0) return null
      const rows = await getJson(
        rest,
        `club_events?select=title,event_date,location&id=in.(${ids.join(",")})` +
          `&kind=eq.event&event_date=lt.${todayISO}&order=event_date.desc&limit=1`,
      )
      const row = rows[0]
      if (!row) return null
      return {
        title: row.title,
        event_date: row.event_date,
        location: row.location ?? null,
        recurs: await titleRecurs(rest, row.title),
      }
    },

    async newPostCount24h(sinceISO) {
      // Prefer:count=exact returns the total in the Content-Range header (Range 0-0
      // keeps the body to a single row).
      const res = await rest(
        `club_events?select=id&status=eq.approved&created_at=gte.${encodeURIComponent(sinceISO)}`,
        { headers: { Prefer: "count=exact", Range: "0-0" } },
      )
      return countFromContentRange(res)
    },

    async newestEvent() {
      const rows = await getJson(
        rest,
        `club_events?select=id,title&status=eq.approved&kind=eq.event&order=created_at.desc&limit=1`,
      )
      const row = rows[0]
      if (!row) return null
      const counts = await goingCounts(rest, [row.id])
      return { title: row.title, going_count: counts.get(row.id) ?? 0 }
    },

    async recentHistory(userId, limit) {
      const rows = await getJson(
        rest,
        `almanac_daily?select=body_text,places_mentioned,date,format_used&user_id=eq.${userId}` +
          `&order=date.desc&limit=${limit}`,
      )
      return rows.map((r: any) => ({
        body_text: r.body_text,
        places_mentioned: r.places_mentioned ?? [],
        date: r.date,
        format_used: r.format_used ?? null,
      }))
    },
  }
}

/** True when the same event title exists more than once (a recurring series). */
async function titleRecurs(rest: Rest, title: string): Promise<boolean> {
  const res = await rest(
    `club_events?select=id&kind=eq.event&title=eq.${encodeURIComponent(title)}`,
    { headers: { Prefer: "count=exact", Range: "0-0" } },
  )
  return countFromContentRange(res) > 1
}

async function myRsvpEventIds(rest: Rest, userId: string): Promise<string[]> {
  const rows = await getJson(rest, `event_rsvps?select=event_id&user_id=eq.${userId}`)
  return rows.map((r: any) => r.event_id).filter(Boolean)
}

async function goingCounts(rest: Rest, eventIds: string[]): Promise<Map<string, number>> {
  const counts = new Map<string, number>()
  if (eventIds.length === 0) return counts
  const rows = await getJson(rest, `event_rsvps?select=event_id&event_id=in.(${eventIds.join(",")})`)
  for (const r of rows) counts.set(r.event_id, (counts.get(r.event_id) ?? 0) + 1)
  return counts
}

async function getJson(rest: Rest, path: string): Promise<any[]> {
  const res = await rest(path)
  if (!res.ok) return []
  try {
    return await res.json()
  } catch {
    return []
  }
}

function countFromContentRange(res: Response): number {
  // Content-Range: "0-0/123" — the total is after the slash.
  const cr = res.headers.get("content-range") ?? ""
  const total = cr.split("/")[1]
  const n = total ? parseInt(total, 10) : 0
  return Number.isFinite(n) ? n : 0
}
