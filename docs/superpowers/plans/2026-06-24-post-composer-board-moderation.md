# Post composer + Activities + Claude moderation — Implementation Plan (v2, Expo)

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use `- [ ]` checkboxes.

**Goal:** Rework the mobile Add-event tab into a 3-kind **Post** composer (Event/Club/Trail) with Claude moderation via a Supabase Edge Function, add an **Activities** tab (Clubs + Trails + admin review queue), and fold Quest into Home — taking the app to 4 calm tabs.

**Architecture:** UI in `apps/mobile` (Expo Router, React Native, theme tokens `C`/`F`/`HAIRLINE`, `react-native-svg` icons). Shared queries in `packages/core` (`createCommunityApi`). Moderation in a Deno Supabase Edge Function. Events/Trails ride on `club_events` (`kind` column); Clubs stay in the separate `clubs` table.

**Tech Stack:** Expo SDK 54 / RN 0.81 / Expo Router 6, TypeScript, Supabase (Postgres + Storage + Edge Functions), Anthropic Messages API.

## Global Constraints

- **No test framework exists.** Verification gate per task = `npx tsc --noEmit -p apps/mobile/tsconfig.json` (and `packages/core` typecheck) clean, plus visual confirmation in the running app for UI tasks. **Do NOT add a test runner.**
- **Active codebase only:** `apps/mobile` + `packages/core`. Never edit `apps/web`.
- Dates via `localDate()` from `@hygge/core`, never `toISOString()`.
- Numbers (dates, counts, length) in `F.mono`.
- Accents one job each: `C.moss700` = approved/primary; `C.clay700` = warning/error (moderation flag) only; sky = brand/focus. Never decorative.
- Surfaces `C.paper*`; text `C.ink/ink2/ink3`; borders `HAIRLINE`.
- Icons: `react-native-svg` components in `components/icons.tsx` — no emoji.
- On-brand bar: calm, neighborly, hyper-local. No badges/streaks/feeds/follower-counts. Real counts only.
- `ANTHROPIC_API_KEY` lives ONLY as a Supabase secret (Edge Function env). Never in the client bundle.
- Match the existing file's style when editing it; surgical changes only.

## File Structure

- `supabase/migration-posts.sql` — **done** (Task 1, committed): `kind`/`length`/`difficulty` + nullable dates.
- `supabase/functions/moderate-post/index.ts` — **create.** Deno moderation function.
- `packages/core/src/types.ts` — **modify.** `PostKind`, `NewTrailInput`, `Trail`.
- `packages/core/src/community.ts` — **modify.** trail + admin-queue + status helpers; `kind='event'` filters.
- `apps/mobile/src/app/(tabs)/add.tsx` — **modify.** Kind picker + adaptive fields + moderation flow.
- `apps/mobile/src/app/(tabs)/activities.tsx` — **create** (rename from `clubs.tsx`). Clubs + Trails + admin queue.
- `apps/mobile/src/app/(tabs)/clubs.tsx` — **delete** (renamed).
- `apps/mobile/src/app/(tabs)/_layout.tsx` — **modify.** 4 tabs; drop quest.
- `apps/mobile/src/components/QuestSection.tsx` — **create.** Quest UI extracted for Home.
- `apps/mobile/src/app/(tabs)/index.tsx` — **modify.** Render `<QuestSection/>`.
- `apps/mobile/src/app/(tabs)/quest.tsx` — **delete** (logic moved to QuestSection).
- `apps/mobile/src/components/TabBar.tsx` (or wherever tab labels/icons live) — **modify** for new tab set.

---

## Task 1 — Migration (DONE)

Already committed (`supabase/migration-posts.sql`): adds `kind`(`event|trail`)/`length`/`difficulty`, nullable `event_date`/`start_time`. No action; the user runs it in Supabase before Task 7.

---

## Task 2 — packages/core: types + helpers

**Files:** Modify `packages/core/src/types.ts`, `packages/core/src/community.ts`.

**Interfaces produced (consumed by Tasks 4 & 5):**
- `type PostKind = 'event' | 'trail'`
- `type NewTrailInput = { title: string; location: string; length?: string; description?: string; image_url?: string }`
- `type Trail = { id: string; title: string; location: string | null; length: string | null; difficulty: string | null; description: string | null; image_url: string | null; status: ClubStatus; created_at: string }`
- `type PendingPost = Trail & { kind: PostKind; event_date: string | null; start_time: string | null }`
- `addEvent(input: NewEventInput, clubId?: string | null, status?: ClubStatus): Promise<void>` (status added; default `'approved'`)
- `addTrail(input: NewTrailInput, status?: ClubStatus): Promise<void>`
- `getTrails(): Promise<Trail[]>`
- `getPendingPosts(): Promise<PendingPost[]>` · `getPendingClubs(): Promise<ClubRow[]>`
- `approvePost(id): Promise<void>` · `rejectPost(id): Promise<void>` · `setClubStatus(id, status): Promise<void>`

- [ ] **Step 1 — types.ts:** after the `NewEventInput` type, add:

```ts
export type PostKind = 'event' | 'trail'

export type NewTrailInput = {
  title: string
  location: string
  length?: string
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
```

- [ ] **Step 2 — community.ts event-reader filters:** in `getTodayEvents`, `getEventsByDate`, `getMonthEventDates`, add `.eq('kind', 'event')` immediately after each `.eq('status', 'approved')`. (Three call sites — see lines ~86, ~161, ~191.)

- [ ] **Step 3 — community.ts `addEvent` status param:** change the signature to `async function addEvent(input: NewEventInput, clubId?: string | null, status: ClubStatus = 'approved')` and use `status` in the inserted `base` object (replace the hardcoded `status: 'approved'`).

- [ ] **Step 4 — community.ts new helpers:** add inside `createCommunityApi` (before the `return`):

```ts
  async function addTrail(input: NewTrailInput, status: ClubStatus = 'approved'): Promise<void> {
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) throw new Error('Not signed in')
    const { error } = await supabase.from('club_events').insert({
      kind: 'trail',
      title: input.title,
      location: input.location,
      length: input.length ?? null,
      description: input.description ?? null,
      image_url: input.image_url ?? null,
      event_date: null,
      start_time: null,
      submitted_by: user.id,
      status,
      club_id: null,
    })
    if (error) throw error
  }

  async function getTrails(): Promise<Trail[]> {
    const { data, error } = await supabase
      .from('club_events').select('*')
      .eq('status', 'approved').eq('kind', 'trail')
      .order('created_at', { ascending: false })
    if (error) throw error
    return (data ?? []).map(mapTrail)
  }

  async function getPendingPosts(): Promise<PendingPost[]> {
    const { data, error } = await supabase
      .from('club_events').select('*')
      .eq('status', 'pending')
      .order('created_at', { ascending: false })
    if (error) throw error
    return (data ?? []).map((e) => ({ ...mapTrail(e), kind: (e.kind ?? 'event') as PostKind, event_date: e.event_date ?? null, start_time: e.start_time ?? null }))
  }

  async function getPendingClubs(): Promise<ClubRow[]> {
    const { data, error } = await supabase
      .from('clubs').select('*')
      .eq('status', 'pending')
      .order('created_at', { ascending: false })
    if (error) throw error
    return (data ?? []) as ClubRow[]
  }

  async function approvePost(id: string): Promise<void> {
    const { error } = await supabase.from('club_events').update({ status: 'approved' }).eq('id', id)
    if (error) throw error
  }
  async function rejectPost(id: string): Promise<void> {
    const { error } = await supabase.from('club_events').update({ status: 'rejected' }).eq('id', id)
    if (error) throw error
  }
  async function setClubStatus(id: string, status: ClubStatus): Promise<void> {
    const { error } = await supabase.from('clubs').update({ status }).eq('id', id)
    if (error) throw error
  }
```

And add this module-level helper near the top of `community.ts` (after imports, outside `createCommunityApi`):

```ts
function mapTrail(e: Record<string, any>): import('./types').Trail {
  return {
    id: e.id, title: e.title,
    location: e.location ?? null, length: e.length ?? null, difficulty: e.difficulty ?? null,
    description: e.description ?? null, image_url: e.image_url ?? null,
    status: e.status, created_at: e.created_at,
  }
}
```

- [ ] **Step 5 — export:** add `addTrail, getTrails, getPendingPosts, getPendingClubs, approvePost, rejectPost, setClubStatus` to the object returned by `createCommunityApi`. Import the new types in `community.ts`'s type import from `./types` (`NewTrailInput`, `Trail`, `PendingPost`, `PostKind`, `ClubRow`, `ClubStatus`).

- [ ] **Step 6 — typecheck:** `npx tsc --noEmit -p packages/core/tsconfig.json` (or the workspace root typecheck). Expected: clean. `apps/mobile` may error until Task 4 — acceptable; gate on `packages/core` clean.

- [ ] **Step 7 — commit:**
```bash
git add packages/core/src/types.ts packages/core/src/community.ts
git commit -m "feat(core): trail posts, admin review queues, status params, kind filters

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3 — Supabase Edge Function: moderate-post

**Files:** Create `supabase/functions/moderate-post/index.ts`.

**Interface produced (consumed by Task 4):** `POST` via `supabase.functions.invoke('moderate-post', { body })` where body = `{ kind, title, location?, description?, length?, image_url? }`; resolves `{ ok: boolean, reason: string }`. Non-2xx on missing key / model failure (client treats as fail-closed).

- [ ] **Step 1 — Read the claude-api skill** for the current model id, the Messages API request shape, and the vision image-source format (URL vs base64). Use what it says; the code below is the starting point.

- [ ] **Step 2 — Write the function** (`supabase/functions/moderate-post/index.ts`). Calls the Anthropic REST API directly with `fetch` (no SDK needed in Deno):

```ts
// Supabase Edge Function: moderate a community post with Claude (text + image).
// Deploy: supabase functions deploy moderate-post
// Secret: supabase secrets set ANTHROPIC_API_KEY=...
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const SYSTEM = `You moderate posts for Hygge, a warm, calm, hyper-local community app for the real town of St. Joseph, Minnesota. Neighbors post events, clubs, and trails.

Approve when the post is a plausible local community post of its stated kind, is not spam/advertising/scam, is not abusive/hateful/harassing, and is not sexual, violent, or otherwise inappropriate. If an image is provided it must also be appropriate. Minor unpolished wording is fine — do not reject for tone alone.

Reject only with a clear, kind, specific reason the poster can act on.

Respond with ONLY a JSON object: {"ok": true|false, "reason": "<short reason; empty when ok>"}`

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), { status, headers: { ...CORS, 'Content-Type': 'application/json' } })

  const key = Deno.env.get('ANTHROPIC_API_KEY')
  if (!key) return json({ ok: false, reason: 'Moderation unavailable.' }, 503)

  let body: any
  try { body = await req.json() } catch { return json({ ok: false, reason: 'Bad request.' }, 400) }

  const facts = [
    `Kind: ${body.kind}`,
    `Title: ${body.title}`,
    body.location ? `Location: ${body.location}` : null,
    body.length ? `Length: ${body.length}` : null,
    body.description ? `Description: ${body.description}` : null,
  ].filter(Boolean).join('\n')

  const content: any[] = [{ type: 'text', text: facts }]
  if (body.image_url) content.push({ type: 'image', source: { type: 'url', url: body.image_url } })

  try {
    const res = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: { 'x-api-key': key, 'anthropic-version': '2023-06-01', 'content-type': 'application/json' },
      body: JSON.stringify({
        model: 'claude-haiku-4-5-20251001', // confirm via claude-api skill
        max_tokens: 200,
        system: SYSTEM,
        messages: [{ role: 'user', content }],
      }),
    })
    if (!res.ok) return json({ ok: false, reason: 'Could not auto-check.' }, 502)
    const data = await res.json()
    const text = (data.content ?? []).filter((b: any) => b.type === 'text').map((b: any) => b.text).join('').trim()
    const match = text.match(/\{[\s\S]*\}/)
    if (!match) return json({ ok: false, reason: 'Could not auto-check.' }, 502)
    const parsed = JSON.parse(match[0])
    return json({ ok: !!parsed.ok, reason: parsed.reason ?? '' })
  } catch {
    return json({ ok: false, reason: 'Could not auto-check.' }, 502)
  }
})
```

- [ ] **Step 3 — verify it parses:** `deno check supabase/functions/moderate-post/index.ts` if Deno is installed; otherwise visually confirm and note it's validated at deploy time. (No project typecheck covers Deno files.)

- [ ] **Step 4 — commit:**
```bash
git add supabase/functions/moderate-post/index.ts
git commit -m "feat(edge): moderate-post Claude moderation function (text + image)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4 — Post composer (rework add.tsx)

**Files:** Modify `apps/mobile/src/app/(tabs)/add.tsx`.

**Consumes:** `api.addEvent(input, null, status)`, `api.addTrail(input, status)`, `api.submitClub(clubInput)`, `uploadEventImage`, `supabase.functions.invoke`, `NewEventInput`/`NewTrailInput`/`ClubInput`/`PostKind` from `@hygge/core`, existing `Field`, `C/F/HAIRLINE`, icons.

> Read the current `add.tsx` fully first — keep its `Field` component, photo-square JSX, `pickPhoto`, `uploadEventImage` usage, and SafeAreaView/ScrollView shell. You are adding a kind picker + adaptive fields + a moderation step around the existing submit, not rewriting the shell.

- [ ] **Step 1 — kind state + picker.** Add `const [kind, setKind] = useState<PostKind>('event')` and broaden form state to hold all fields used across kinds (`title, event_date, start_time, location, description, length, difficulty, host, schedule, vibe, expectations`). Render three pill `Pressable`s (Event/Club/Trail) above the photo square, moss-tinted when active (mirror the active-pill style from the existing tab bar / clubs filter). Title and the photo square stay shown for all kinds.

- [ ] **Step 2 — adaptive fields** (render by `kind`, reusing `Field`):
  - `event`: Date, Time, Location (required), Description — as today.
  - `club`: Host, When (`schedule`), Where (`location`), Vibe, About (`description`), What to expect (`expectations`). (Mirror the field set the old Start-a-club form in `clubs.tsx` used → `ClubInput`.)
  - `trail`: Location/trailhead (required), Length, Difficulty, Description.

- [ ] **Step 3 — validation** by kind: title always required; event needs date+time+location; trail needs location; club needs title (name) + host. Show `C.clay700` error text (existing pattern).

- [ ] **Step 4 — moderation + submit.** Replace the current `submit` with:

```tsx
const submit = async () => {
  const v = validate()           // returns string | null per Step 3
  if (v) { setError(v); return }
  setError(null); setSubmitting(true)
  try {
    const image_url = photo ? (await uploadEventImage(photo)) ?? undefined : undefined
    // Run Claude moderation (fail-closed → pending).
    let pending = false
    try {
      const { data, error } = await supabase.functions.invoke('moderate-post', {
        body: { kind, title: form.title.trim(), location: form.location?.trim(), description: form.description?.trim(), length: form.length?.trim(), image_url },
      })
      if (error || !data) pending = true
      else if (!data.ok) {
        setError(data.reason || 'That didn’t pass review — tweak it and try again.')
        Haptics.notificationAsync(Haptics.NotificationFeedbackType.Warning)
        setSubmitting(false); return
      }
    } catch { pending = true }
    const status = pending ? 'pending' : 'approved'

    if (kind === 'event') {
      await api.addEvent({ title: form.title.trim(), event_date: form.event_date, start_time: form.start_time.trim(), location: form.location.trim(), description: form.description, image_url }, null, status)
    } else if (kind === 'trail') {
      await api.addTrail({ title: form.title.trim(), location: form.location.trim(), length: form.length, description: form.description, image_url }, status)
    } else {
      // club → existing clubs system (submitClub already sets pending for non-admins;
      // pass the moderation result through where the API allows). Reuse submitClub.
      await api.submitClub({ name: form.title.trim(), host: form.host, schedule: form.schedule, location: form.location, vibe: form.vibe, description: form.description, expectations: form.expectations })
    }
    Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success)
    resetForm()
    router.replace(kind === 'event' ? '/(tabs)' : '/(tabs)/activities')
  } catch {
    setError('Could not post — try again.')
  } finally {
    setSubmitting(false)
  }
}
```

> Note on Club + moderation: `submitClub` already routes non-admin clubs to `pending`, so a club flagged or unreviewed still lands in the admin queue. If moderation returned `!ok`, we already returned above. Keep it simple — do not add a status param to `submitClub` in this task.

- [ ] **Step 5 — imports/title.** Add `import { supabase } from '../../lib/supabase'` (confirm the export name). Change the screen title from "Add an event" to "New post". Update the submit button label to "Post".

- [ ] **Step 6 — typecheck:** `npx tsc --noEmit -p apps/mobile/tsconfig.json`. Expected: clean (after Task 2 landed). Fix any type errors in the new code.

- [ ] **Step 7 — commit:**
```bash
git add apps/mobile/src/app/(tabs)/add.tsx
git commit -m "feat(mobile): Post composer — kind picker (event/club/trail) + Claude moderation

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5 — Activities tab (Clubs + Trails + admin queue)

**Files:** Rename `apps/mobile/src/app/(tabs)/clubs.tsx` → `activities.tsx` (`git mv`); modify it.

**Consumes:** existing club list/detail/join code; `api.getTrails`, `api.getPendingPosts`, `api.getPendingClubs`, `api.approvePost`, `api.rejectPost`, `api.setClubStatus`, `isAdminEmail`.

- [ ] **Step 1 — `git mv`** `clubs.tsx` → `activities.tsx`. Keep the existing club list, `ClubDetail` (join/leave), and `MetaRow`/`Section`/`CField` helpers. **Remove the standalone "Start a club" form** (creation now lives in the Post composer); also remove its now-unused state/handlers. Rename the default export component to `Activities` and the header title to "Activities".

- [ ] **Step 2 — load trails + admin queues.** Add state `trails`, `pendingPosts`, `pendingClubs`, and load them in the existing effect alongside `getApprovedClubs` (admin queues only when `isAdminEmail(user?.email)`).

- [ ] **Step 3 — render groups.** Below the existing Clubs list, add a **Trails** section (a simple card per trail: title, `location · length · difficulty` in `F.mono`, optional photo, description). Reuse the visual weight of the existing club cards.

- [ ] **Step 4 — admin "Waiting for review".** At the top (admin only, when any pending exists): list pending posts + pending clubs, each with Approve / Decline `Pressable`s calling `approvePost`/`rejectPost` (posts) or `setClubStatus(id,'approved'|'rejected')` (clubs); on success remove the row from local state and refresh the relevant list.

- [ ] **Step 5 — typecheck** `npx tsc --noEmit -p apps/mobile/tsconfig.json`. (Tab still routes once Task 6 updates `_layout`; the screen compiles independently now.)

- [ ] **Step 6 — commit:**
```bash
git add -A apps/mobile/src/app/(tabs)/
git commit -m "feat(mobile): Activities tab — clubs + trails + admin review queue

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6 — Quest into Home + 4-tab nav

**Files:** Create `apps/mobile/src/components/QuestSection.tsx`; modify `index.tsx`, `_layout.tsx`, the TabBar (labels/icons); delete `quest.tsx`.

- [ ] **Step 1 — extract QuestSection.** Move the quest UI + logic from `quest.tsx` into `apps/mobile/src/components/QuestSection.tsx` (a self-contained component using `api.getTodayQuest`, `getQuestCompletionCount`, `hasUserCompletedQuest`, `completeQuest`; and the admin quest-setter gated by `isAdminEmail`). Keep the existing styles/copy.

- [ ] **Step 2 — render on Home.** In `index.tsx`, import and render `<QuestSection />` near the bottom of the Home `ScrollView` (after `AroundTown`, before the closing padding). Confirm spacing matches surrounding sections.

- [ ] **Step 3 — drop the Quest tab.** In `_layout.tsx`, remove `<Tabs.Screen name="quest" />`, rename `<Tabs.Screen name="clubs" />` → `name="activities"`. Resulting tabs: `index`, `activities`, `calendar`, `add`. Delete `apps/mobile/src/app/(tabs)/quest.tsx`.

- [ ] **Step 4 — TabBar labels/icons.** Update the custom TabBar (and `components/icons.tsx` if needed): label `add` → "Post", `activities` → "Activities"; remove the Quest entry; ensure each of the 4 routes has a label + icon. Add an Activities icon (e.g. a compass/trail-marker) if none fits; mirror existing icon style.

- [ ] **Step 5 — full typecheck + bundle:** `npx tsc --noEmit -p apps/mobile/tsconfig.json` clean, then `cd apps/mobile && npx expo export --platform web` succeeds (proves the whole app bundles, no missing routes/imports).

- [ ] **Step 6 — commit:**
```bash
git add -A apps/mobile/
git commit -m "feat(mobile): fold Quest into Home, go to 4 tabs (Home/Activities/Calendar/Post)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 7 — End-to-end verification

**Files:** none (verification only).

- [ ] **Step 1 — user prerequisites.** Confirm the user has: run `migration-posts.sql`; deployed the function (`supabase functions deploy moderate-post`); set `supabase secrets set ANTHROPIC_API_KEY=…`. If the secret is unset, the function returns 503 → posts land in **pending** by design; note that in verification.

- [ ] **Step 2 — run the app.** Use the project run/preview tooling (see `.claude/TOOLKIT.md`) — `npm run site` (Expo web) or a simulator. Screenshot at phone width.

- [ ] **Step 3 — exercise paths:** kind picker swaps fields; Event with photo → moderates → appears on Home today; Trail → appears under Trails in Activities; Club → appears in Clubs (pending if non-admin); off-brand text → flagged with clay reason, nothing saved; forced failure / no key → lands in admin "Waiting for review"; Approve → goes live. Quest shows on Home; 4 tabs render.

- [ ] **Step 4 — on-brand diff:** tokens (`C`/`F`), moss=approve / clay=flag, no emoji, numbers in `F.mono`, calm copy. Capture final screenshots.

- [ ] **Step 5 — commit any polish.**

---

## Self-Review (plan author)

- **Spec coverage:** name→T4; photo→existing+T4; kinds Event/Club/Trail→T4; Club reuses clubs→T4 Step 4; Trail on club_events→T1/T2/T4; moderation incl. image→T3/T4; warn-resubmit→T4; fail-closed→pending+admin queue→T2/T4/T5; Edge Function→T3; Activities (clubs+trails+queue)→T5; Quest→Home + 4 tabs→T6; events-only timeline→T2. Covered.
- **Placeholders:** core + edge function fully coded; RN UI tasks give complete net-new logic (moderation/submit, helper signatures) and precise transform instructions against named existing code (legitimate — the screens exist and must be matched, not retyped). Model id routed through claude-api skill in T3.
- **Type consistency:** `PostKind`, `NewTrailInput`, `Trail`, `PendingPost`, `addTrail`, `getTrails`, `getPendingPosts`, `getPendingClubs`, `approvePost`, `rejectPost`, `setClubStatus`, `addEvent(…, status?)` defined in T2 and consumed with matching signatures in T4/T5.
- **Known nuance:** Club moderation is best-effort (reuses `submitClub`'s existing pending/approved-by-admin behavior; an explicit `!ok` flag still blocks at the composer). Documented in T4 Step 4 so the reviewer doesn't read it as a gap.
```
