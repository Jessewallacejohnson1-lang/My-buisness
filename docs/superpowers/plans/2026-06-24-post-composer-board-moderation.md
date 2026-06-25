# Post composer + Board + Claude moderation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Add Event form with an Instagram-style multi-kind **Post** composer (Event/Club/Trail/Notice + optional photo), gate every post behind a Claude moderation route (text + image), and add a **Board** tab surfacing undated posts plus an admin manual-approval queue.

**Architecture:** All UI lives in the single client component `app/community/page.tsx` (per existing pattern — one file, in-file `<svg>` icons, inline styles). DB logic lives in `lib/community.ts` against the reused `club_events` table. Photos go to a public Supabase Storage bucket. Moderation runs in a server route `app/api/moderate-post/route.ts` using the already-installed `@anthropic-ai/sdk`.

**Tech Stack:** Next.js 16 (App Router), TypeScript, Tailwind v4 (`@theme` tokens), Supabase (Postgres + Storage + RLS), `@anthropic-ai/sdk` (already a dependency).

## Global Constraints

- **No test framework exists.** Per project definition-of-done, each task's verification gate is `npm run build` (typecheck) passing, plus visual confirmation in the running app via the preview tools at **~390px width** where UI changed. Do **not** add a test runner.
- **Dates:** always `localDate()` from `lib/db.ts`; never `toISOString()`.
- **Numbers** (dates, counts, length): `font-mono` with `tabular-nums`.
- **Accents have one job:** `moss-700` = approved/primary action; `clay-700` = warning/error (moderation flag) only; `sky-600` = brand/focus. Never decorative.
- **Surfaces** `paper*`; **text** `ink`/`ink-2`/`ink-3`; **borders** `border-black/[0.07]` (`rgba(0,0,0,0.07)`).
- **Icons:** inline `<svg>` only — no emoji.
- **On-brand bar:** calm, warm, neighborly, hyper-local. No badges/streaks/feeds/follower-counts. Real counts only.
- **Anthropic key** is server-side only (`ANTHROPIC_API_KEY`); never import the SDK into a `'use client'` file.
- Reuse existing form styling helpers `labelStyle` / `fieldStyle` / `.hygge-field` and the moss submit button already defined in `app/community/page.tsx`.

---

## File Structure

- `supabase/migration-posts.sql` — **create.** Schema + storage bucket + RLS for posts.
- `lib/community.ts` — **modify.** New `PostKind`, `NewPostInput`, `BoardPost` types; `addPost`, `uploadPostImage`, `getBoardPosts`, `getPendingPosts`, `approvePost`, `rejectPost`; add `kind='event'` filter to event readers.
- `app/api/moderate-post/route.ts` — **create.** Claude moderation endpoint.
- `app/community/page.tsx` — **modify.** Replace `AddEventTab` with `PostTab`; add `BoardTab`; extend `Tab` type, `TABS`, nav icons, routing.

---

## Task 1: Database migration + storage bucket

**Files:**
- Create: `supabase/migration-posts.sql`

**Interfaces:**
- Produces: `club_events` columns `kind`, `image_url`, `cadence`, `length`, `difficulty`; nullable `event_date`/`start_time`; public Storage bucket `post-images` with insert (own-path) + public-read RLS. Consumed by every later task.

- [ ] **Step 1: Write the migration file**

Create `supabase/migration-posts.sql`:

```sql
-- migration-posts.sql — multi-kind posts on club_events + photo storage.
-- Run AFTER migration-community.sql and migration-quests.sql.

-- 1. Kind + photo + kind-specific columns on the reused posts table.
alter table public.club_events
  add column if not exists kind       text not null default 'event',
  add column if not exists image_url  text,
  add column if not exists cadence    text,   -- Club: e.g. "Thursdays 6pm"
  add column if not exists length     text,   -- Trail: e.g. "2.4 mi"
  add column if not exists difficulty text;   -- Trail: e.g. "Easy"

-- Constrain kind to the four supported values.
alter table public.club_events
  drop constraint if exists club_events_kind_check;
alter table public.club_events
  add constraint club_events_kind_check
  check (kind in ('event', 'club', 'trail', 'notice'));

-- 2. Only Events require a date/time; other kinds are undated.
alter table public.club_events alter column event_date drop not null;
alter table public.club_events alter column start_time drop not null;

-- 3. Photo storage: public bucket, signed-in users upload under their own uid.
insert into storage.buckets (id, name, public)
values ('post-images', 'post-images', true)
on conflict (id) do nothing;

drop policy if exists "post-images public read" on storage.objects;
create policy "post-images public read" on storage.objects
  for select using (bucket_id = 'post-images');

drop policy if exists "post-images owner insert" on storage.objects;
create policy "post-images owner insert" on storage.objects
  for insert to authenticated with check (
    bucket_id = 'post-images'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
```

- [ ] **Step 2: Verify SQL is internally valid (no DB run in this step)**

Run: `grep -c "add column if not exists" supabase/migration-posts.sql`
Expected: `5` (kind, image_url, cadence, length, difficulty).

- [ ] **Step 3: Commit**

```bash
git add supabase/migration-posts.sql
git commit -m "feat(db): migration for multi-kind posts + post-images storage bucket"
```

> **Hand-off note for the user (not a code step):** This migration + bucket must be run once in the Supabase SQL editor before posting works. Surface this to the user at execution time.

---

## Task 2: Lib types + helpers

**Files:**
- Modify: `lib/community.ts`

**Interfaces:**
- Consumes: Task 1 columns; existing `supabase`, `localDate`, `currentUserId`, `isAdminEmail`, `TimelineEvent`, `ClubStatus`.
- Produces:
  - `type PostKind = 'event' | 'club' | 'trail' | 'notice'`
  - `type NewPostInput = { kind: PostKind; title: string; image_url?: string | null; event_date?: string | null; start_time?: string | null; location?: string | null; description?: string | null; cadence?: string | null; length?: string | null; difficulty?: string | null }`
  - `type BoardPost = { id: string; kind: PostKind; title: string; image_url: string | null; location: string | null; description: string | null; cadence: string | null; length: string | null; difficulty: string | null; status: ClubStatus; created_at: string }`
  - `uploadPostImage(file: File): Promise<string>` — returns public URL
  - `addPost(input: NewPostInput, status?: ClubStatus): Promise<void>`
  - `getBoardPosts(): Promise<BoardPost[]>` — approved club/trail/notice
  - `getPendingPosts(): Promise<BoardPost[]>` — admin queue
  - `approvePost(id: string): Promise<void>` / `rejectPost(id: string): Promise<void>`

- [ ] **Step 1: Add the `kind='event'` filter to event readers**

In `lib/community.ts`, in `getTodayEvents` (the `.eq('status', 'approved')` chain) add a kind filter. Change:

```ts
    .from('club_events')
    .select('*')
    .eq('status', 'approved')
    .eq('event_date', today)
```
to:
```ts
    .from('club_events')
    .select('*')
    .eq('status', 'approved')
    .eq('kind', 'event')
    .eq('event_date', today)
```

Apply the **same** `.eq('kind', 'event')` insertion to `getEventsByDate` (after its `.eq('status','approved')`) and to `getMonthEventDates`. (Search for `.eq('status', 'approved')` — there are three event readers; add the kind filter to each. Leave club helpers untouched.)

- [ ] **Step 2: Replace `NewEventInput`/`addEvent` with post types + helpers**

Replace the existing block (the `NewEventInput` type and `addEvent` function, currently ~lines 261-279) with:

```ts
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
```

- [ ] **Step 3: Typecheck**

Run: `npm run build`
Expected: build succeeds. If `app/community/page.tsx` still imports `addEvent`/`NewEventInput`, the build will error here — that's expected and fixed in Task 4. To verify just this file in isolation first, run `npx tsc --noEmit lib/community.ts` is not reliable (needs project config); instead proceed knowing Task 4 restores the build. **Gate for this task:** `npx tsc --noEmit` shows errors ONLY in `app/community/page.tsx` (the `addEvent` import), none in `lib/community.ts`.

- [ ] **Step 4: Commit**

```bash
git add lib/community.ts
git commit -m "feat(lib): post types, image upload, board + pending post helpers"
```

---

## Task 3: Claude moderation API route

**Files:**
- Create: `app/api/moderate-post/route.ts`

**Interfaces:**
- Consumes: `ANTHROPIC_API_KEY` env, `@anthropic-ai/sdk`.
- Produces: `POST /api/moderate-post` accepting JSON `{ kind, title, location?, description?, cadence?, length?, difficulty?, image_url? }`; responds `200 { ok: boolean, reason: string }` on success, or non-200 on any failure (client treats non-200 as fail-closed → pending).

- [ ] **Step 1: Read the claude-api skill first**

Before writing the route, invoke the `claude-api` skill (the task names Anthropic/Claude) to confirm the current model id, message/vision block shape, and structured-output approach. Use the model id it gives for a fast, cheap judge (a Haiku-class model is appropriate). Do not hardcode a model from memory.

- [ ] **Step 2: Write the route**

Create `app/api/moderate-post/route.ts`:

```ts
import Anthropic from '@anthropic-ai/sdk'
import { NextResponse } from 'next/server'

// Server-only: keeps ANTHROPIC_API_KEY off the client.
export const runtime = 'nodejs'

type Body = {
  kind: string
  title: string
  location?: string | null
  description?: string | null
  cadence?: string | null
  length?: string | null
  difficulty?: string | null
  image_url?: string | null
}

const SYSTEM = `You moderate posts for Hygge, a warm, calm, hyper-local community app for the real town of St. Joseph, Minnesota. Neighbors post events, clubs, trails, and notices.

Approve a post when it is a plausible local community post of its stated kind, is not spam/advertising/scam, is not abusive/hateful/harassing, and is not sexual, violent, or otherwise inappropriate. If an image is provided, it must also be appropriate (nothing sexual, graphic, hateful, or unsafe). Tone should read like a neighbor, but minor wording is fine — do not reject for being unpolished.

Reject only with a clear, kind, specific reason the poster can act on.

Respond with ONLY a JSON object: {"ok": true|false, "reason": "<short reason, empty string when ok>"}`

export async function POST(req: Request) {
  const key = process.env.ANTHROPIC_API_KEY
  if (!key) {
    return NextResponse.json({ ok: false, reason: 'Moderation unavailable.' }, { status: 503 })
  }

  let body: Body
  try {
    body = await req.json()
  } catch {
    return NextResponse.json({ ok: false, reason: 'Bad request.' }, { status: 400 })
  }

  const anthropic = new Anthropic({ apiKey: key })

  const facts = [
    `Kind: ${body.kind}`,
    `Title: ${body.title}`,
    body.location ? `Location: ${body.location}` : null,
    body.cadence ? `When: ${body.cadence}` : null,
    body.length ? `Length: ${body.length}` : null,
    body.difficulty ? `Difficulty: ${body.difficulty}` : null,
    body.description ? `Description: ${body.description}` : null,
  ].filter(Boolean).join('\n')

  // Build content: text always; image block only when a photo URL is present.
  const content: Anthropic.ContentBlockParam[] = [{ type: 'text', text: facts }]
  if (body.image_url) {
    content.push({ type: 'image', source: { type: 'url', url: body.image_url } })
  }

  try {
    const msg = await anthropic.messages.create({
      // Use the model id confirmed via the claude-api skill (fast judge tier).
      model: 'claude-haiku-4-5-20251001',
      max_tokens: 200,
      system: SYSTEM,
      messages: [{ role: 'user', content }],
    })
    const text = msg.content
      .filter((b): b is Anthropic.TextBlock => b.type === 'text')
      .map((b) => b.text)
      .join('')
      .trim()
    const match = text.match(/\{[\s\S]*\}/)
    if (!match) throw new Error('No JSON in model output')
    const parsed = JSON.parse(match[0]) as { ok?: boolean; reason?: string }
    return NextResponse.json({ ok: !!parsed.ok, reason: parsed.reason ?? '' })
  } catch {
    // Fail-closed: caller saves the post as pending for manual review.
    return NextResponse.json({ ok: false, reason: 'Could not auto-check.' }, { status: 502 })
  }
}
```

> If the claude-api skill reports a different vision-source shape (e.g. base64 vs url) or a newer Haiku model id, use that instead — keep the `{ok, reason}` contract identical.

- [ ] **Step 3: Typecheck**

Run: `npm run build`
Expected: build succeeds (Task 4 not yet done may still error in page.tsx — if so, gate on `npx tsc --noEmit` showing no errors in `app/api/moderate-post/route.ts`).

- [ ] **Step 4: Commit**

```bash
git add app/api/moderate-post/route.ts
git commit -m "feat(api): Claude moderation route for posts (text + image)"
```

---

## Task 4: Post composer (replace AddEventTab)

**Files:**
- Modify: `app/community/page.tsx`

**Interfaces:**
- Consumes: `NewPostInput`, `PostKind`, `addPost`, `uploadPostImage` from `lib/community.ts`; existing `labelStyle`, `fieldStyle`, `haptic`.
- Produces: `PostTab` component; client moderation flow (pass/flag/pending). Consumed by Task 6 routing.

- [ ] **Step 1: Update imports**

In `app/community/page.tsx`, change the `lib/community` import: remove `addEvent` and `NewEventInput`; add `addPost`, `uploadPostImage`, and types `NewPostInput`, `PostKind`. (Also add `getBoardPosts`, `getPendingPosts`, `approvePost`, `rejectPost`, `BoardPost` now — used in Task 5 — to avoid a second import edit.)

- [ ] **Step 2: Replace the `AddEventTab` function with `PostTab`**

Replace the entire `AddEventTab` function (the block starting `// ── Add Event tab ──` through its closing `}`) with:

```tsx
// ── Post tab ───────────────────────────────────────────────────────────────

const POST_KINDS: { id: PostKind; label: string }[] = [
  { id: 'event', label: 'Event' },
  { id: 'club', label: 'Club' },
  { id: 'trail', label: 'Trail' },
  { id: 'notice', label: 'Notice' },
]

function PostTab({ onSuccess }: { onSuccess: (dest: 'home' | 'board') => void }) {
  const todayYmd = (() => {
    const d = new Date()
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
  })()

  const [kind, setKind] = useState<PostKind>('event')
  const [form, setForm] = useState({
    title: '', event_date: todayYmd, start_time: '', location: '',
    description: '', cadence: '', length: '', difficulty: '',
  })
  const [imageUrl, setImageUrl] = useState<string | null>(null)
  const [uploading, setUploading] = useState(false)
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const fileRef = useRef<HTMLInputElement>(null)

  const set = (field: keyof typeof form) => (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) =>
    setForm((f) => ({ ...f, [field]: e.target.value }))

  const pickKind = (k: PostKind) => { if (k !== kind) haptic('select'); setKind(k); setError(null) }

  const onFile = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file) return
    setUploading(true); setError(null)
    try {
      const url = await uploadPostImage(file)
      setImageUrl(url); haptic('tap')
    } catch {
      setError('Could not upload that photo — try another.')
    } finally {
      setUploading(false)
      if (fileRef.current) fileRef.current.value = ''
    }
  }

  function validate(): string | null {
    if (!form.title.trim()) return 'Add a title.'
    if (kind === 'event' && (!form.event_date || !form.start_time.trim() || !form.location.trim()))
      return 'Events need a date, time, and location.'
    if (kind === 'trail' && !form.location.trim()) return 'Trails need a location or trailhead.'
    if (kind === 'notice' && !form.description.trim()) return 'Add a few words to your notice.'
    return null
  }

  function buildInput(): NewPostInput {
    const t = (s: string) => (s.trim() ? s.trim() : null)
    return {
      kind,
      title: form.title.trim(),
      image_url: imageUrl,
      event_date: kind === 'event' ? form.event_date : null,
      start_time: kind === 'event' ? t(form.start_time) : null,
      location: kind === 'club' || kind === 'event' || kind === 'trail' || kind === 'notice' ? t(form.location) : null,
      description: t(form.description),
      cadence: kind === 'club' ? t(form.cadence) : null,
      length: kind === 'trail' ? t(form.length) : null,
      difficulty: kind === 'trail' ? t(form.difficulty) : null,
    }
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    const v = validate()
    if (v) { setError(v); return }
    setError(null); setSubmitting(true)
    const input = buildInput()
    const dest: 'home' | 'board' = kind === 'event' ? 'home' : 'board'
    try {
      let verdict: { ok: boolean; reason: string }
      try {
        const res = await fetch('/api/moderate-post', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            kind, title: input.title, location: input.location, description: input.description,
            cadence: input.cadence, length: input.length, difficulty: input.difficulty,
            image_url: input.image_url,
          }),
        })
        if (!res.ok) throw new Error('moderation unavailable')
        verdict = await res.json()
      } catch {
        // Fail-closed: save as pending for manual admin review.
        await addPost(input, 'pending')
        haptic('warn')
        setError(null)
        onSuccess('board')
        return
      }
      if (!verdict.ok) {
        setError(verdict.reason || 'That didn’t pass review — tweak it and try again.')
        haptic('warn')
        return
      }
      await addPost(input, 'approved')
      haptic('success')
      onSuccess(dest)
    } catch {
      setError('Could not post — try again.')
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <div style={{ padding: '24px 18px' }}>
      <p className="font-sans" style={{ fontSize: 11, color: 'var(--color-ink-3)', textTransform: 'uppercase', letterSpacing: '0.16em', marginBottom: 3 }}>New</p>
      <h1 className="font-display" style={{ fontSize: 24, color: 'var(--color-ink)', marginBottom: 18 }}>New post</h1>

      {/* Kind picker */}
      <div style={{ display: 'flex', gap: 8, marginBottom: 18, flexWrap: 'wrap' }}>
        {POST_KINDS.map((k) => {
          const active = k.id === kind
          return (
            <button key={k.id} type="button" onClick={() => pickKind(k.id)} className="press hygge-tap"
              style={{
                padding: '8px 16px', borderRadius: 999, cursor: 'pointer',
                fontFamily: 'var(--font-sans)', fontSize: 13, fontWeight: 600,
                border: active ? '1px solid var(--color-moss-700)' : '1px solid rgba(0,0,0,0.07)',
                background: active ? 'rgba(45,69,48,0.10)' : 'var(--color-paper)',
                color: active ? 'var(--color-moss-700)' : 'var(--color-ink-2)',
              }}>
              {k.label}
            </button>
          )
        })}
      </div>

      <form onSubmit={handleSubmit} style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
        {/* Image square */}
        <div>
          <input ref={fileRef} type="file" accept="image/*" onChange={onFile} style={{ display: 'none' }} />
          {imageUrl ? (
            <div style={{ position: 'relative', width: '100%', aspectRatio: '1 / 1', borderRadius: 14, overflow: 'hidden', border: '1px solid rgba(0,0,0,0.07)' }}>
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={imageUrl} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
              <button type="button" onClick={() => setImageUrl(null)} aria-label="Remove photo" className="press"
                style={{ position: 'absolute', top: 8, right: 8, width: 30, height: 30, borderRadius: 999, border: 'none', cursor: 'pointer', background: 'rgba(0,0,0,0.55)', color: '#fff', fontSize: 16, lineHeight: '30px' }}>×</button>
            </div>
          ) : (
            <button type="button" onClick={() => fileRef.current?.click()} disabled={uploading} className="press hygge-tap"
              style={{
                width: '100%', aspectRatio: '1 / 1', borderRadius: 14, cursor: uploading ? 'wait' : 'pointer',
                border: '1.5px dashed rgba(0,0,0,0.14)', background: 'var(--color-paper-100)',
                display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 8,
                color: 'var(--color-ink-3)', fontFamily: 'var(--font-sans)',
              }}>
              <svg width="34" height="34" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
                <rect x="3" y="3" width="18" height="18" rx="3" /><circle cx="8.5" cy="9" r="1.5" /><path d="M21 15l-5-5L5 21" />
              </svg>
              <span style={{ fontSize: 13 }}>{uploading ? 'Uploading…' : 'Add a photo · optional'}</span>
            </button>
          )}
        </div>

        {/* Title — always */}
        <div>
          <label style={labelStyle}>Title</label>
          <input className="hygge-field" style={fieldStyle} placeholder={kind === 'club' ? 'St. Joe Run Club' : kind === 'trail' ? 'Millstream Loop' : kind === 'notice' ? 'Free firewood on Birch St' : 'Saturday Farmers Market'} value={form.title} onChange={set('title')} />
        </div>

        {/* Event fields */}
        {kind === 'event' && (
          <>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
              <div><label style={labelStyle}>Date</label><input type="date" className="hygge-field" style={fieldStyle} value={form.event_date} onChange={set('event_date')} /></div>
              <div><label style={labelStyle}>Time</label><input className="hygge-field" style={fieldStyle} placeholder="7am" value={form.start_time} onChange={set('start_time')} /></div>
            </div>
            <div><label style={labelStyle}>Location</label><input className="hygge-field" style={fieldStyle} placeholder="Millstream Park" value={form.location} onChange={set('location')} /></div>
          </>
        )}

        {/* Club fields */}
        {kind === 'club' && (
          <>
            <div><label style={labelStyle}>When <span style={optHint}>· optional</span></label><input className="hygge-field" style={fieldStyle} placeholder="Thursdays 6pm" value={form.cadence} onChange={set('cadence')} /></div>
            <div><label style={labelStyle}>Where <span style={optHint}>· optional</span></label><input className="hygge-field" style={fieldStyle} placeholder="Local Blend coffee" value={form.location} onChange={set('location')} /></div>
          </>
        )}

        {/* Trail fields */}
        {kind === 'trail' && (
          <>
            <div><label style={labelStyle}>Trailhead / location</label><input className="hygge-field" style={fieldStyle} placeholder="Lake Wobegon Trail, CR-2" value={form.location} onChange={set('location')} /></div>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
              <div><label style={labelStyle}>Length <span style={optHint}>· optional</span></label><input className="hygge-field" style={fieldStyle} placeholder="2.4 mi" value={form.length} onChange={set('length')} /></div>
              <div><label style={labelStyle}>Difficulty <span style={optHint}>· optional</span></label><input className="hygge-field" style={fieldStyle} placeholder="Easy" value={form.difficulty} onChange={set('difficulty')} /></div>
            </div>
          </>
        )}

        {/* Description — all kinds (required for Notice) */}
        <div>
          <label style={labelStyle}>Description {kind !== 'notice' && <span style={optHint}>· optional</span>}</label>
          <textarea className="hygge-field" style={{ ...fieldStyle, minHeight: 84, resize: 'vertical' }} placeholder="Tell neighbors what to expect…" value={form.description} onChange={set('description')} />
        </div>

        {error && <p className="font-sans" style={{ fontSize: 13, color: 'var(--color-clay-700)' }}>{error}</p>}

        <button type="submit" disabled={submitting || uploading} className="press hygge-tap"
          style={{
            marginTop: 4, padding: '14px', borderRadius: 12, border: 'none',
            background: submitting || uploading ? 'var(--color-paper-200)' : 'var(--color-moss-700)',
            color: submitting || uploading ? 'var(--color-ink-3)' : 'var(--color-paper)',
            fontSize: 15, fontWeight: 600, cursor: submitting || uploading ? 'not-allowed' : 'pointer', fontFamily: 'var(--font-sans)',
          }}>
          {submitting ? 'Posting…' : 'Post'}
        </button>
      </form>
    </div>
  )
}

const optHint: React.CSSProperties = { textTransform: 'none', letterSpacing: 0, color: 'var(--color-ink-3)' }
```

- [ ] **Step 3: Add the `useRef` import**

Ensure `useRef` is in the React import at the top of the file (the file already imports `useState`/`useEffect` from `'react'`). Add `useRef` to that list if missing.

- [ ] **Step 4: Typecheck**

Run: `npm run build`
Expected: still errors at the routing call site (`<AddEventTab .../>` no longer exists) — that's fixed in Task 6. Gate: no typecheck errors *inside* the new `PostTab` body. If you prefer a green build before Task 6, do Task 6 Step 1 (routing swap) now, then build.

- [ ] **Step 5: Commit**

```bash
git add app/community/page.tsx
git commit -m "feat(community): Instagram-style PostTab with kind picker, photo upload, moderation flow"
```

---

## Task 5: Board tab + admin review queue

**Files:**
- Modify: `app/community/page.tsx`

**Interfaces:**
- Consumes: `getBoardPosts`, `getPendingPosts`, `approvePost`, `rejectPost`, `BoardPost`, `getCurrentUser`/`isAdminEmail` (existing admin gating pattern), `haptic`.
- Produces: `BoardTab` component. Consumed by Task 6 routing.

- [ ] **Step 1: Add the `BoardTab` function**

Add after `PostTab` in `app/community/page.tsx`:

```tsx
// ── Board tab ──────────────────────────────────────────────────────────────

const KIND_LABEL: Record<string, string> = { club: 'Clubs', trail: 'Trails', notice: 'Notices' }

function BoardCard({ post }: { post: BoardPost }) {
  const meta = [
    post.cadence,
    post.length,
    post.difficulty,
    post.location,
  ].filter(Boolean).join(' · ')
  return (
    <article style={{ borderRadius: 14, border: '1px solid rgba(0,0,0,0.07)', background: 'var(--color-paper)', overflow: 'hidden' }}>
      {post.image_url && (
        // eslint-disable-next-line @next/next/no-img-element
        <img src={post.image_url} alt="" style={{ width: '100%', aspectRatio: '16 / 10', objectFit: 'cover', display: 'block' }} />
      )}
      <div style={{ padding: '12px 14px' }}>
        <h3 className="font-display" style={{ fontSize: 17, color: 'var(--color-ink)', marginBottom: meta ? 4 : 0 }}>{post.title}</h3>
        {meta && <p className="font-mono tabular-nums" style={{ fontSize: 12, color: 'var(--color-ink-3)', marginBottom: post.description ? 6 : 0 }}>{meta}</p>}
        {post.description && <p className="font-sans" style={{ fontSize: 14, color: 'var(--color-ink-2)', lineHeight: 1.5 }}>{post.description}</p>}
      </div>
    </article>
  )
}

function BoardTab({ isAdmin }: { isAdmin: boolean }) {
  const [posts, setPosts] = useState<BoardPost[]>([])
  const [pending, setPending] = useState<BoardPost[]>([])
  const [loading, setLoading] = useState(true)
  const [busyId, setBusyId] = useState<string | null>(null)

  useEffect(() => {
    let alive = true
    async function load() {
      const [board, queue] = await Promise.all([
        getBoardPosts(),
        isAdmin ? getPendingPosts() : Promise.resolve([] as BoardPost[]),
      ])
      if (!alive) return
      setPosts(board); setPending(queue); setLoading(false)
    }
    load()
    return () => { alive = false }
  }, [isAdmin])

  const decide = async (id: string, approve: boolean) => {
    setBusyId(id)
    try {
      if (approve) { await approvePost(id); haptic('success') } else { await rejectPost(id); haptic('tap') }
      setPending((p) => p.filter((x) => x.id !== id))
      if (approve) setPosts(await getBoardPosts())
    } catch {
      // leave row in queue on failure
    } finally {
      setBusyId(null)
    }
  }

  const groups = (['club', 'trail', 'notice'] as const).map((k) => ({ k, items: posts.filter((p) => p.kind === k) }))

  return (
    <div style={{ padding: '24px 18px' }}>
      <p className="font-sans" style={{ fontSize: 11, color: 'var(--color-ink-3)', textTransform: 'uppercase', letterSpacing: '0.16em', marginBottom: 3 }}>Around town</p>
      <h1 className="font-display" style={{ fontSize: 24, color: 'var(--color-ink)', marginBottom: 18 }}>The board</h1>

      {/* Admin review queue */}
      {isAdmin && pending.length > 0 && (
        <section style={{ marginBottom: 26 }}>
          <p className="font-sans" style={{ fontSize: 12, fontWeight: 600, color: 'var(--color-clay-700)', marginBottom: 10 }}>Waiting for review · {pending.length}</p>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
            {pending.map((post) => (
              <div key={post.id} style={{ borderRadius: 14, border: '1px solid rgba(0,0,0,0.07)', background: 'var(--color-paper-100)', overflow: 'hidden' }}>
                <BoardCard post={post} />
                <div style={{ display: 'flex', gap: 8, padding: '10px 14px' }}>
                  <button type="button" disabled={busyId === post.id} onClick={() => decide(post.id, true)} className="press hygge-tap"
                    style={{ flex: 1, padding: '10px', borderRadius: 10, border: 'none', cursor: 'pointer', background: 'var(--color-moss-700)', color: 'var(--color-paper)', fontFamily: 'var(--font-sans)', fontSize: 14, fontWeight: 600 }}>Approve</button>
                  <button type="button" disabled={busyId === post.id} onClick={() => decide(post.id, false)} className="press hygge-tap"
                    style={{ flex: 1, padding: '10px', borderRadius: 10, cursor: 'pointer', background: 'var(--color-paper)', border: '1px solid rgba(0,0,0,0.07)', color: 'var(--color-ink-2)', fontFamily: 'var(--font-sans)', fontSize: 14, fontWeight: 600 }}>Decline</button>
                </div>
              </div>
            ))}
          </div>
        </section>
      )}

      {loading ? (
        <p className="font-sans" style={{ fontSize: 14, color: 'var(--color-ink-3)' }}>Loading…</p>
      ) : posts.length === 0 ? (
        <p className="font-sans" style={{ fontSize: 14, color: 'var(--color-ink-3)', lineHeight: 1.6 }}>Nothing on the board yet. Clubs, trails, and notices neighbors share will show up here.</p>
      ) : (
        groups.filter((g) => g.items.length > 0).map((g) => (
          <section key={g.k} style={{ marginBottom: 24 }}>
            <p className="font-sans" style={{ fontSize: 12, fontWeight: 600, color: 'var(--color-ink-3)', textTransform: 'uppercase', letterSpacing: '0.1em', marginBottom: 10 }}>{KIND_LABEL[g.k]}</p>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
              {g.items.map((post) => <BoardCard key={post.id} post={post} />)}
            </div>
          </section>
        ))
      )}
    </div>
  )
}
```

- [ ] **Step 2: Typecheck** (green once Task 6 wires routing; otherwise gate on no errors inside `BoardTab`).

Run: `npm run build`

- [ ] **Step 3: Commit**

```bash
git add app/community/page.tsx
git commit -m "feat(community): Board tab with grouped posts + admin review queue"
```

---

## Task 6: Wire tabs, nav icons, and routing

**Files:**
- Modify: `app/community/page.tsx`

**Interfaces:**
- Consumes: `PostTab`, `BoardTab`.
- Produces: reachable Post + Board tabs; the build goes green.

- [ ] **Step 1: Extend the `Tab` type and routing**

Change the `Tab` type (`type Tab = 'home' | 'calendar' | 'add' | 'quest'`) to:

```ts
type Tab = 'home' | 'calendar' | 'post' | 'board' | 'quest'
```

Update the content router block:
```tsx
          {tab === 'home' && <HomeTab onNav={switchTab} />}
          {tab === 'calendar' && <CalendarTab />}
          {tab === 'add' && <AddEventTab onSuccess={() => setTab('timeline')} />}
          {tab === 'quest' && <QuestTab isAdmin={isAdmin} />}
```
to:
```tsx
          {tab === 'home' && <HomeTab onNav={switchTab} />}
          {tab === 'calendar' && <CalendarTab />}
          {tab === 'post' && <PostTab onSuccess={(dest) => setTab(dest)} />}
          {tab === 'board' && <BoardTab isAdmin={isAdmin} />}
          {tab === 'quest' && <QuestTab isAdmin={isAdmin} />}
```

> Note: the old `onSuccess={() => setTab('timeline')}` referenced a non-existent `'timeline'` id; the new `PostTab` routes to `'home'` or `'board'`. If any other code references `'add'` or `'timeline'` as a Tab, update those references to the new ids (search the file for `'add'` and `'timeline'`).

- [ ] **Step 2: Update the `TABS` array**

Change:
```ts
  const TABS: { id: Tab; label: string }[] = [
    { id: 'home', label: 'Home' },
    { id: 'calendar', label: 'Calendar' },
    { id: 'add', label: 'Add' },
    { id: 'quest', label: 'Quest' },
  ]
```
to:
```ts
  const TABS: { id: Tab; label: string }[] = [
    { id: 'home', label: 'Home' },
    { id: 'calendar', label: 'Calendar' },
    { id: 'post', label: 'Post' },
    { id: 'board', label: 'Board' },
    { id: 'quest', label: 'Quest' },
  ]
```

- [ ] **Step 3: Update the nav icon function for the new ids**

Find the icon component/function that switches on tab id (it special-cases `id === 'add'` for stroke width and renders a `+` glyph — see the `strokeWidth: id === 'add'` line near the top of the file). Update it so:
- the `'post'` id renders the existing plus/compose icon (rename the `id === 'add'` branch condition to `id === 'post'`, including the `strokeWidth` ternary), and
- add a `'board'` branch rendering this inline icon:

```tsx
// board: a simple noticeboard / grid of cards
<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
  <rect x="3" y="4" width="18" height="16" rx="2" /><path d="M3 9h18" /><path d="M9 9v11" />
</svg>
```
Match the surrounding icon code's return structure (the other branches show the exact JSX shape to mirror). Ensure every tab id in `TABS` has a corresponding icon branch.

- [ ] **Step 4: Build green**

Run: `npm run build`
Expected: **build succeeds with no errors.** Fix any remaining references to `'add'`/`'timeline'`/`AddEventTab`/`addEvent`.

- [ ] **Step 5: Lint**

Run: `npm run lint`
Expected: passes (note: `<img>` usages carry the `eslint-disable-next-line @next/next/no-img-element` comments already included).

- [ ] **Step 6: Commit**

```bash
git add app/community/page.tsx
git commit -m "feat(community): wire Post + Board tabs into nav and routing"
```

---

## Task 7: End-to-end verification in the running app

**Files:** none (verification only).

- [ ] **Step 1: Ensure DB + env are ready**

Confirm with the user that `supabase/migration-posts.sql` has been run and the `post-images` bucket exists, and that `ANTHROPIC_API_KEY` is set in `.env.local`. If the key is absent, the moderation route returns 503 and posts will land in the **pending** queue by design — note this in the verification.

- [ ] **Step 2: Launch and screenshot the composer at 390px**

Use the preview tools (`preview_start` → `preview_resize` to 390px → navigate to `/community` → `preview_screenshot`). Per `.claude/TOOLKIT.md`. Confirm:
- Post tab shows the kind picker (Event/Club/Trail/Notice) and the photo square.
- Switching kind swaps the fields (Event date/time/location; Club when/where; Trail trailhead/length/difficulty; Notice description-only).

- [ ] **Step 3: Exercise each path**

- Create an Event with a photo → passes moderation (key set) → appears in Home timeline today.
- Create a Club → appears under Clubs on the Board.
- (Admin) With the key unset or a forced failure, submit a post → lands in **Waiting for review**; Approve → it appears on the Board.
- Submit obviously off-brand text → moderation flags it; the clay reason shows; no row inserted.

- [ ] **Step 4: Diff against tokens / on-brand bar**

Confirm: numbers render `font-mono tabular-nums`; accents used per role (moss=approve, clay=flag); borders `rgba(0,0,0,0.07)`; no emoji; calm/neighborly copy. Capture a final screenshot.

- [ ] **Step 5: Commit any token/polish fixes**

```bash
git add -A
git commit -m "fix(community): verification polish for post composer + board"
```

---

## Self-Review (completed by plan author)

- **Spec coverage:** naming→T4/T6; optional photo→T1/T2/T4; kinds+real columns→T1/T2/T4; Board tab→T5/T6; Supabase Storage→T1/T2; moderation incl. image→T3/T4; warn-and-resubmit→T4; fail-closed→pending+admin queue→T2/T4/T5; timeline stays events-only→T2. All covered.
- **Placeholders:** none — every code step contains full code; the only deferred detail is the Claude model id/vision-source shape, explicitly routed through the `claude-api` skill in T3 with a concrete default.
- **Type consistency:** `NewPostInput`, `BoardPost`, `PostKind`, `addPost(input, status)`, `uploadPostImage`, `getBoardPosts`/`getPendingPosts`/`approvePost`/`rejectPost` are defined in T2 and consumed with matching signatures in T4/T5; `Tab` ids (`home/calendar/post/board/quest`) consistent across T6.
```
