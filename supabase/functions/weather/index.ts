// Supabase Edge Function: weather — the weather tracker and school closings (BP app docs/plans/school-activities,
// tickets 07 and 08; Jesse, 2026-11-13: "bp should have a weather tracker in backend").
//
// pg_cron's private.wake_weather calls this every 15 minutes. It reads the town's National Weather Service alerts
// (api.weather.gov, free, no key) once an hour. While a winter alert is out it reads WJON's closings list (AM 1240,
// St. Cloud) every 15 minutes from 7 to 10 PM and 5 AM to noon; otherwise once, at 6:15 AM. Last winter every
// school-day change came with such an alert out at least 18 hours before the call (BP app
// docs/plans/school-activities/assets/07-snow-days.md). Each day's list goes whole to public.apply_school_closings,
// which writes the News and calls off that day's Events. The alerts stay in the backend: the app never shows them.
//
// The pacing is private.weather's (when the alerts and the list were last read), not the caller's, so a second call
// from anyone reads nothing new: verify_jwt is off.
//
// Deploy: supabase functions deploy weather --project-ref lxdgwhvqjqmqliobwjpi, which keeps verify_jwt off from
// supabase/config.toml. Composio's SUPABASE_DEPLOY_FUNCTION turns it back on: follow it with SUPABASE_UPDATE_A_FUNCTION,
// verify_jwt false, as live-scores does.

const UA = { "User-Agent": "BlockPartyBot/1.0 (+https://blockpartystjoe.com)" }
const TZ = "America/Chicago"
// ponytail: one town; loop over private.weather's rows when a second town has its zone.
const TOWN = "st-joseph-mn"
// WJON files a day's list under Closings or under Weather (Dec 9 and Nov 25, 2025 were under Weather only).
const FEEDS = ["https://wjon.com/category/closings/feed/", "https://wjon.com/category/weather/feed/"]
const WINTER = /winter|blizzard|ice storm|extreme cold|cold weather|wind chill|freezing (rain|drizzle)|snow squall/i
const MINUTE = 60_000

export type Kind = "closed" | "early" | "late" | "elearning"
type District = { key: string; name: RegExp; teams: string[]; sources: string[];
                  news?: { source_name: string; place_entry_id: string } }
export type Alert = { event: string; onset: string | null; ends: string | null }
export type State = { zone: string; alerts: Alert[]; alerts_read_at: string | null; list_read_at: string | null }
export type Line = { district: string; kind: Kind; words: string; title: string }
type Rpc = (name: string, body: unknown) => Promise<unknown>
type Get = (url: string) => Promise<string>

// The schools whose Events are in St. Joseph's Town feed, by the name WJON's list gives them (lower case, "saint"
// written "st."). Teams are their `teams` ids, co-ops included; sources their registry names. Only the town's own
// schools get a News card (Jesse, 2026-11-13); the rest only have their Events called off.
export const DISTRICTS: District[] = [
  { key: "st-cloud", name: /st\. ?cloud (area|public schools|schools?\b)/,
    teams: ["apollo", "tech", "kennedy", "north-junior-high", "south-junior-high", "apollo-cathedral", "st-cloud-rocori"],
    sources: ["Apollo High School", "Tech High School", "Kennedy Community School"],
    news: { source_name: "Kennedy Community School", place_entry_id: "kennedy-community-school" } },
  { key: "catholic-community-schools", name: /catholic community schools?\b/,
    teams: ["cathedral", "apollo-cathedral"], sources: ["Cathedral High School", "St. Joseph Catholic School"],
    news: { source_name: "St. Joseph Catholic School", place_entry_id: "st-joseph-catholic-school" } },
  { key: "sartell", name: /sartell\b/, teams: ["sartell", "sartell-sauk-rapids"], sources: ["Sartell High School"] },
  { key: "sauk-rapids-rice", name: /sauk rapids\b/, teams: ["sauk-rapids-rice", "sartell-sauk-rapids"],
    sources: ["Sauk Rapids-Rice High School"] },
  { key: "rocori", name: /rocori\b/, teams: ["rocori", "st-cloud-rocori"], sources: ["ROCORI High School"] },
  { key: "st-johns-prep", name: /st\. ?john'?s prep/, teams: ["st-johns-prep"], sources: ["St. John's Prep"] },
  { key: "albany", name: /albany\b/, teams: ["albany"], sources: ["Albany High School"] },
  { key: "holdingford", name: /holdingford\b/, teams: ["holdingford"], sources: ["Holdingford High School"] },
  { key: "kimball", name: /kimball\b/, teams: ["kimball"], sources: ["Kimball Area High School"] },
  { key: "royalton", name: /royalton\b/, teams: ["royalton"], sources: ["Royalton High School"] },
  { key: "eden-valley-watkins", name: /eden valley\b/, teams: ["eden-valley-watkins"],
    sources: ["Eden Valley-Watkins High School"] },
]

// A heading names its kind loosely: "SCHOOLS (2 hours late):", "SCHOOLS CLOSING EARLY:", "SCHOOLS (Closed):".
const HOURS = String.raw`(\d+|one|two|three)[- ]hours?`
const HEADING_KINDS: [Kind, RegExp][] = [
  ["elearning", /e-?learning/], ["early", /early|dismiss/], ["late", /late|delay/], ["closed", /closed|closing|no school/],
]
// A line overrides its heading only with a strong phrase in its first sentence, the first one named: "Catholic
// Community Schools will be closed. Cathedral will move to an e-learning day." is closed, "Sauk Rapids-Rice
// (e-learning)" under Closed is e-learning. A side note never does: "No morning early childhood classes", "Kid Care
// opening delayed until 9", "Normal dismissal time" stay their heading's kind. Out early wins a tie with closed.
const LINE_KINDS: [Kind, RegExp][] = [
  ["elearning", /(?<!\bnot an? )\be-?learning\b|\bremote learning\b|\bdistance learning\b/],
  ["early", new RegExp(String.raw`\b${HOURS} early\b|\bclos(e|es|ing) early\b|\bclos(e|es|ing) at (\d|noon)|` +
                       String.raw`\b(dismiss|releas)\w* (students )?(early|at (\d|noon))`)],
  ["late", new RegExp(String.raw`\b${HOURS} (late|delay)|\blate start\b|\bdelayed start\b|\bstart(s|ing)? late\b`)],
  ["closed", /\b(will be|is|are) closed\b|\bno school\b|\bno classes\b|\bnot have classes\b/],
]
const RANK: Record<Kind, number> = { late: 1, early: 2, elearning: 3, closed: 4 }
const NUMBERS: Record<string, string> = { one: "1", two: "2", three: "3" }

function firstKind(text: string, kinds: [Kind, RegExp][]): Kind | null {
  let best: { at: number; kind: Kind } | null = null
  for (const [kind, re] of kinds) {
    const m = re.exec(text)
    if (m && (!best || m.index < best.at)) best = { at: m.index, kind }
  }
  return best?.kind ?? null
}

// The first sentence: up to a full stop that isn't "St.", "a.m.", "p.m." or an initial.
const firstSentence = (text: string) => text.split(/(?<!\bst|\b[ap]\.m|\b[a-z])\.(?:\s|$)/)[0]

export function kindOf(line: string, heading: Kind | null): Kind | null {
  return firstKind(firstSentence(line), LINE_KINDS) ?? heading ?? firstKind(line, LINE_KINDS)
}

function titleOf(kind: Kind, words: string): string {
  const h = new RegExp(HOURS).exec(words)?.[1]
  const n = h ? (NUMBERS[h] ?? h) : null
  const hours = n === "1" ? "1 Hour" : `${n} Hours`
  if (kind === "closed") return "No School"
  if (kind === "elearning") return "E-Learning Day"
  if (kind === "early") return n ? `Out ${hours} Early` : "Out Early"
  return n ? `${hours} Late` : "Late Start"
}

const ENTITIES: Record<string, string> = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " ",
                                           rsquo: "'", lsquo: "'", ldquo: '"', rdquo: '"', ndash: "–", mdash: "—" }
function decode(s: string): string {
  return s.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (all, e: string) =>
    e[0] === "#" ? String.fromCodePoint(e[1].toLowerCase() === "x" ? parseInt(e.slice(2), 16) : parseInt(e.slice(1)))
      : ENTITIES[e.toLowerCase()] ?? all)
}

// Block tags end a line and a list item starts one as "-- "; any other tag goes with no space, since WJON's pasted text
// splits words with them ("F<span>oley</span>", Dec 9).
function textLines(html: string): string[] {
  const s = html.replace(/<(script|style|noscript|svg)[^>]*>[\s\S]*?<\/\1>/gi, " ")
    .replace(/<li\b[^>]*>/gi, "\n-- ")
    .replace(/<br\s*\/?>|<\/?(p|div|li|ul|ol|h[1-6]|tr|table|section|article|blockquote)\b[^>]*>/gi, "\n")
    .replace(/<[^>]+>/g, "")
  return decode(s).split("\n").map((l) => l.replace(/\s+/g, " ").trim()).filter(Boolean)
}

const plain = (s: string) => s.toLowerCase().replace(/[’‘]/g, "'").replace(/\bsaint\b/g, "st.").replace(/\s+/g, " ")

// A day's post: the first <article id="post-…"> (later ones are other posts), from the line after "( WJON News )"
// to "If you have a weather-related announcement". A page without that marker isn't the post (a moved or blocked
// page) and throws: read as empty, it would take back every closing that day. A line starting "SCHOOLS" or
// "Private schools", colon or not, opens a school section; any other short line ending in a colon ("MISCELLANEOUS:")
// closes it. Each "-", "--" or bullet line in a school section starts with a school's name ("Prince of Peace Lutheran
// School in St. Cloud" is not St. Cloud's). A line for one of ours with no kind in its words or its heading is
// `unread`: the run fails rather than guess.
export function parseList(html: string): { lines: Line[]; unread: string[] } {
  const start = html.indexOf('<article id="post-')
  const next = start < 0 ? -1 : html.indexOf("<article", start + 10)
  const all = textLines(start < 0 ? html : html.slice(start, next < 0 ? undefined : next))
  const from = all.findIndex((l) => /\(\s*WJON News\s*\)/i.test(l))
  if (from < 0) throw new Error("not a WJON list post: no \"( WJON News )\" line")
  const lines: Line[] = []
  const unread: string[] = []
  let section: Kind | null | false = false
  let heading = ""
  for (const raw of all.slice(from + 1)) {
    if (/if you have a weather|cancellations line/i.test(raw)) break
    const item = /^[-–—•*]+\s*(.*)$/.exec(raw)
    if (!item) {
      if (/^((private|public|area|catholic) )?schools?\b/i.test(raw)) {
        heading = plain(raw)
        section = firstKind(heading, HEADING_KINDS)
      } else if (/:\s*$/.test(raw) && raw.length <= 40) {
        section = false
      }
      continue
    }
    if (section === false) continue
    const words = item[1]
    const text = plain(words).replace(/^the /, "")
    for (const d of DISTRICTS) {
      if (d.name.exec(text)?.index !== 0) continue
      const kind = kindOf(text, section)
      if (!kind) unread.push(words)
      // A title's hours come from the line, else its heading ("SCHOOLS (2 hours late):" over "-- Sartell").
      else lines.push({ district: d.key, kind, words, title: titleOf(kind, `${text} ${heading}`) })
      break
    }
  }
  return { lines: strongest(lines), unread }
}

// A school named twice keeps its strongest kind.
function strongest(lines: Line[]): Line[] {
  const kept = new Map<string, Line>()
  for (const l of lines) if (!kept.has(l.district) || RANK[l.kind] > RANK[kept.get(l.district)!.kind]) kept.set(l.district, l)
  return [...kept.values()]
}

const MONTHS = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october",
                "november", "december"]

// A feed item that may be a day's list: "Weather Related Announcements for Thursday, April 2nd, 2026", "Cancellations
// and Closings – May 2nd".
const LIST_TITLE = /announcement|closing|delay/i

// The day a list's title is for, with the year of when it was posted when the title has none ("… For Wednesday,
// February 18th"). Null when the title isn't a list's or names no day.
export function dayOf(title: string, posted: Date): string | null {
  const t = decode(title)
  const m = /\b(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\.?\s+(\d{1,2})(?:st|nd|rd|th)?\b(?:,?\s+(\d{4}))?/i.exec(t)
  const month = m ? MONTHS.findIndex((x) => x.startsWith(m[1].toLowerCase().slice(0, 3))) : -1
  if (!LIST_TITLE.test(t) || !m || month < 0) return null
  const near = (y: number) => Math.abs(Date.UTC(y, month, +m[2]) - posted.getTime())
  const y0 = posted.getUTCFullYear()
  const year = m[3] ? +m[3] : [y0 - 1, y0, y0 + 1].reduce((a, b) => (near(b) < near(a) ? b : a))
  return `${year}-${String(month + 1).padStart(2, "0")}-${m[2].padStart(2, "0")}`
}

export function feedPosts(xml: string): { title: string; link: string; posted: Date }[] {
  return [...xml.matchAll(/<item>([\s\S]*?)<\/item>/g)].map(([, item]) => {
    const tag = (n: string) => (new RegExp(`<${n}>([\\s\\S]*?)</${n}>`).exec(item)?.[1] ?? "")
      .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/, "$1").trim()
    return { title: decode(tag("title")), link: tag("link"), posted: new Date(tag("pubDate")) }
  })
}

// Chicago's clock: the day as YYYY-MM-DD and the minutes since midnight.
export function local(t: Date): { day: string; minutes: number } {
  const p = Object.fromEntries(new Intl.DateTimeFormat("en-CA", { timeZone: TZ, year: "numeric", month: "2-digit",
    day: "2-digit", hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).formatToParts(t).map((x) => [x.type, x.value]))
  return { day: `${p.year}-${p.month}-${p.day}`, minutes: +p.hour * 60 + +p.minute }
}

const addDays = (day: string, n: number) => new Date(Date.parse(`${day}T12:00:00Z`) + n * 86_400_000).toISOString().slice(0, 10)

export function stormy(alerts: Alert[], now: Date): boolean {
  return alerts.some((a) => WINTER.test(a.event) && (!a.ends || Date.parse(a.ends) > now.getTime()))
}

export const alertsDue = (now: Date, s: State) => !s.alerts_read_at || now.getTime() - Date.parse(s.alerts_read_at) >= 55 * MINUTE

// While a winter alert is out: every read 7 to 10 PM (the districts promise a night call by 9) and 5 AM to noon
// (morning calls by 6, early dismissals mid-morning). Otherwise the 6:15 read alone, after District 742's 6:00
// promise. Never twice within 13 minutes; a failed read isn't saved, so the next wake tries again.
export function listDue(now: Date, storm: boolean, lastRead: string | null): boolean {
  if (lastRead && now.getTime() - Date.parse(lastRead) < 13 * MINUTE) return false
  const { day, minutes: m } = local(now)
  if (storm) return (m >= 19 * 60 && m < 22 * 60 + 15) || (m >= 5 * 60 && m < 12 * 60 + 15)
  if (m < 6 * 60 + 15 || m >= 6 * 60 + 45) return false
  const last = lastRead ? local(new Date(lastRead)) : null
  return !(last && last.day === day && last.minutes >= 6 * 60 + 15)
}

export async function readAlerts(zone: string, get: Get): Promise<Alert[]> {
  const body = JSON.parse(await get(`https://api.weather.gov/alerts/active?zone=${zone}`))
  return (body.features ?? []).map((f: { properties: Record<string, string | null> }) => f.properties)
    .filter((p: Record<string, string | null>) => p.status === "Actual" && p.messageType !== "Cancel")
    .map((p: Record<string, string | null>) => ({ event: p.event ?? "", onset: p.onset ?? null, ends: p.ends ?? p.expires ?? null }))
}

// Today's and tomorrow's lists. A day's posts are read together and sent as one list, each school at its strongest
// kind (a second post for the same day must not take back the first's closings). A day whose post can't be read is
// left as it was and named in `failed`; the other day still goes. A list-like title posted in the last day and a half
// whose day can't be read is named in `unsure`, so a change in WJON's wording reaches the 8:00 email (a story about a
// restaurant closing is one too, and harmless).
export async function readLists(now: Date, get: Get) {
  const today = local(now).day
  const wanted = new Set([today, addDays(today, 1)])
  const byDay = new Map<string, string[]>()
  const failed: string[] = []
  const unsure: string[] = []
  for (const feed of FEEDS) {
    for (const p of feedPosts(await get(feed))) {
      const day = dayOf(p.title, p.posted)
      if (!day && LIST_TITLE.test(p.title) && now.getTime() - p.posted.getTime() < 36 * 60 * MINUTE) {
        unsure.push(`can't read the day of WJON's post "${p.title}"`)
      }
      if (!day || !wanted.has(day)) continue
      const links = byDay.get(day) ?? []
      if (!links.includes(p.link)) byDay.set(day, [...links, p.link])
    }
  }
  const days: { day: string; url: string; lines: Line[] }[] = []
  for (const [day, links] of byDay) {
    try {
      const lines: Line[] = []
      for (const link of links) {
        const read = parseList(await get(link))
        if (read.unread.length) throw new Error(`a line it can't read: ${read.unread[0]}`)
        lines.push(...read.lines)
      }
      days.push({ day, url: links[0], lines: strongest(lines) })
    } catch (e) {
      failed.push(`WJON's list for ${day}: ${e instanceof Error ? e.message : e}`)
    }
  }
  return { days, failed, unsure: [...new Set(unsure)] }
}

export function payload(lines: Line[]) {
  return lines.map((l) => {
    const d = DISTRICTS.find((x) => x.key === l.district)!
    return { ...l, teams: d.teams, sources: d.sources, news: d.news ?? null }
  })
}

// One wake: the alerts when due, then the list when due. A failure is saved with its reason and the run goes on to
// the list; the 8:00 email names it. The run first claims the town (public.claim_weather): a second call within 5
// minutes, from anyone, reads nothing.
export async function run(rpc: Rpc, get: Get, now = new Date()) {
  const state = (await rpc("claim_weather", { p_town: TOWN })) as State | null
  if (!state) return { busy: true }
  let alerts = state.alerts
  const did: Record<string, unknown> = {}
  const failed = async (e: unknown) => {
    const why = e instanceof Error ? e.message : String(e)
    did.error = why
    await rpc("save_weather", { p_town: TOWN, p_error: why })
  }
  if (alertsDue(now, state)) {
    try {
      alerts = await readAlerts(state.zone, get)
      await rpc("save_weather", { p_town: TOWN, p_alerts: alerts })
      did.alerts = alerts.length
    } catch (e) { await failed(e) }
  }
  if (listDue(now, stormy(alerts, now), state.list_read_at)) {
    try {
      const { days, failed: why, unsure } = await readLists(now, get)
      for (const d of days) {
        did[d.day] = await rpc("apply_school_closings", { p_day: d.day, p_url: d.url, p_closings: payload(d.lines) })
      }
      did.lists = days.length
      // A day that failed is read again at the next wake: the list isn't marked read.
      if (why.length) await failed([...why, ...unsure].join("; "))
      else if (unsure.length) await rpc("save_weather", { p_town: TOWN, p_list_read: true, p_error: unsure.join("; ") })
      else await rpc("save_weather", { p_town: TOWN, p_list_read: true })
    } catch (e) { await failed(e) }
  }
  return did
}

// One request at a time, a second apart, as the registry's polite fetch does.
let lastGet = 0
export async function politeGet(url: string): Promise<string> {
  const wait = lastGet + 1000 - Date.now()
  if (wait > 0) await new Promise((r) => setTimeout(r, wait))
  lastGet = Date.now()
  const res = await fetch(url, { headers: { ...UA, Accept: "application/geo+json, application/xml, text/html" },
                                 signal: AbortSignal.timeout(20_000) })
  if (!res.ok) throw new Error(`${new URL(url).hostname}: HTTP ${res.status}`)
  return await res.text()
}

declare const EdgeRuntime: { waitUntil(p: Promise<unknown>): void }

// Only where Deno runs it: the tests import this file in Node (supabase/tests/weather_function.test.mjs).
if (typeof Deno !== "undefined") Deno.serve(() => {
  const url = Deno.env.get("SUPABASE_URL")
  const key = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}")["default"]
  if (!url || !key) return Response.json({ error: "misconfigured" }, { status: 500 })
  const rpc = async (name: string, body: unknown) => {
    const res = await fetch(`${url}/rest/v1/rpc/${name}`, {
      method: "POST",
      headers: { apikey: key, Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
      body: JSON.stringify(body),
    })
    const text = await res.text()
    if (!res.ok) throw new Error(`${name}: ${res.status} ${text}`)
    return text ? JSON.parse(text) : null
  }
  EdgeRuntime.waitUntil(run(rpc, politeGet).then((did) => console.log("[weather]", JSON.stringify(did)))
    .catch(async (e) => {
      console.error("[weather]", e)
      await rpc("save_weather", { p_town: TOWN, p_error: e instanceof Error ? e.message : String(e) }).catch(() => {})
    }))
  return Response.json({ started: true }, { status: 202 })
})
