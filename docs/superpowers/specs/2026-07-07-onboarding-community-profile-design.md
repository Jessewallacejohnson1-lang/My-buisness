# Onboarding — Community Profile (name · interests · avatar → Supabase)

**Date:** 2026-07-07
**Branch:** `mapbox-map-tab`
**Status:** Approved design, ready for implementation plan.

## Overview

Expand first-run onboarding from `hello → interests → map` into a warm, bounded
wizard that also **collects real customer data** (name, interests, profile
picture) and **persists it to Supabase**. Adapts the three Hypelist reference
screens ("What are you into?", "Let's get you set up", "Add a profile picture")
into Hygge's hyper-local St. Joseph community context.

The existing coral **Map intro** (`MapIntroView`) stays the emotional finale.

### Goals
- Photo-card interest picker (transfer the reference card DNA), St. Joe taxonomy.
- Name step + avatar step, both new.
- Persist name + interests + avatar_url to Supabase, per-user, RLS-guarded.
- Premium motion + a full Reduce-Motion path, matching `MapIntroView`'s discipline.
- Every screen verified in the simulator via a per-screen screenshot loop.

### Non-goals (YAGNI)
- Editing the profile after onboarding (a Settings/profile screen is out of scope here).
- Social features (following, friends), public profiles.
- Migrating or touching the wellness app's `profiles` table.
- Multi-photo galleries; avatar is a single image.

## 1. Flow & screens

```
Welcome  →  [ Name  ·  Interests  ·  Avatar ]  →  Map intro (finale)
 (hello)        └──── progress bar + back chevron ────┘      (unchanged CTA → onDone)
```

`OnboardingView` keeps its `onDone: () -> Void` contract (called by `RootView`'s
first-run gate). New internal `Step` enum: `.hello, .name, .interests, .avatar, .map`.
Progress bar (3 segments) + back chevron render only on name/interests/avatar.
Back preserves all captured state. Transitions: cross-fade + slide, matching the
current `.easeInOut` house style.

### Screen states
- **Welcome** — unchanged copy/layout ("Get started" → advances to `.name`).
- **Name** — "What should we call you?", large centered `TextField`, auto-focus,
  ~24-char cap, trimmed. "Continue" enabled when non-empty. Personalizes later
  copy ("A few things you're into, Alex?").
- **Interests** — "What are you into around town?", vertically scrolling sections
  of **2-column photo cards** (see §2, §5), gentle "Pick a few" (min 1, encourages
  more). Sticky coral "Continue" pill with live count.
- **Avatar** — "Add a profile picture", circular well (empty = soft ring + camera
  glyph), tap → `PhotosPicker`, selected = image in white-ringed circle (ref #3).
  "Continue" + "Skip for now". Upload on advance (best-effort, non-blocking).
- **Map** — `MapIntroView { finish() }`, unchanged. CTA "Explore the map".

### Commit points
- Interests commit to **UserDefaults immediately** on the interests-step Continue
  (so "Suggested for you" matching works at once).
- The **Supabase upsert** (display_name, interests, avatar_url, onboarded_at=now())
  fires when leaving the avatar step (Continue or Skip), best-effort. `onboarded`
  local flag is set at the true end (`finish()`), not mid-flow.

## 2. Interest taxonomy

18 categories in 5 sections. Each has a stable `id`, a display `label`, a photo
asset, and a keyword list wired into the **existing** `Interests.matches(_:_:)`
engine (unchanged signature). Landlocked-MN adaptation: "beaches" → Lakes & Swimming.

| id | label | section | sample keywords |
|---|---|---|---|
| `trails_hiking` | Trails & Hiking | Outdoors & Nature | hike, trail, walk, lake wobegon trail, woodland |
| `lakes_swimming` | Lakes & Swimming | Outdoors & Nature | lake, swim, beach, paddle, kayak, canoe, dock |
| `parks_gardens` | Parks & Gardens | Outdoors & Nature | park, garden, millstream, picnic, playground |
| `biking` | Biking | Outdoors & Nature | bike, cycle, ride, gravel, cycling |
| `coffee` | Coffee Shops | Food & Drink | coffee, café, espresso, local blend, bad habit, latte |
| `dining` | Restaurants & Dining | Food & Drink | restaurant, dinner, lunch, dining, krewe, brunch, supper |
| `farmers_market` | Farmers Market | Food & Drink | farmers market, market, produce, vendor, farm |
| `breweries` | Breweries & Taprooms | Food & Drink | brew, brewery, taproom, beer, cider, tap |
| `live_music` | Live Music | Community & Culture | music, concert, band, live, open mic, choir |
| `art_exhibits` | Art & Exhibits | Community & Culture | art, exhibit, gallery, paint, craft, pottery, maker |
| `faith` | Faith & Fellowship | Community & Culture | church, faith, mass, parish, worship, abbey, st. john |
| `festivals` | Festivals & Fairs | Community & Culture | festival, fair, fest, parade, joetown, celebration |
| `books` | Library & Books | Community & Culture | book, read, library, story, author, lecture, class |
| `fitness_yoga` | Fitness & Yoga | Active & Wellness | yoga, fitness, gym, workout, pilates, stretch |
| `sports_leagues` | Sports & Leagues | Active & Wellness | sport, league, softball, soccer, pickleball, hockey, team |
| `health_wellness` | Health & Wellness | Active & Wellness | health, wellness, clinic, screening, meditation, care |
| `families_kids` | Families & Kids | Families & Social | kid, family, child, parent, youth, story time |
| `volunteering` | Volunteering & Service | Families & Social | volunteer, service, donate, charity, food shelf, drive |

Tunable — add Games & Trivia / Fishing / Birding later by appending a row + asset.
Old ids (`outdoors`, `music_arts`, `food`, …) are dropped from the picker; unknown
stored ids simply don't match, so no migration is required (fresh install base).

## 3. Imagery (hybrid)

- **Seed images:** art-directed, editorial, tightly-framed photos per category —
  one consistent warm palette + natural light, small-Minnesota-town feel — bundled
  in `Assets.xcassets` as `interest-<id>` (e.g. `interest-trails_hiking`).
  Generated via an image model, hand-selected for quality (no slop, framed 4:3).
- **Resolver:** `InterestImage.resolve(id)` returns the real local override if a
  file `interest-<id>` exists in a bundled `LocalPhotos` catalog, else the seed
  asset. Dropping a real St. Joe photo under the override name wins with **zero
  code changes**.
- Honest framing: seeds are art-directed until Jesse's real photos land.

## 4. Data model (Supabase)

The wellness app owns `profiles`; this community app gets its **own** table.

### `public.town_profiles`
```sql
create table if not exists public.town_profiles (
  user_id      uuid primary key default auth.uid()
               references auth.users(id) on delete cascade,
  display_name text,
  avatar_url   text,
  interests    text[] not null default '{}',
  onboarded_at timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
alter table public.town_profiles enable row level security;
create policy "town_profiles_select_own" on public.town_profiles
  for select using (auth.uid() = user_id);
create policy "town_profiles_insert_own" on public.town_profiles
  for insert with check (auth.uid() = user_id);
create policy "town_profiles_update_own" on public.town_profiles
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
```

### `avatars` storage bucket (public)
Path convention `{user_id}/avatar-{ts}.jpg` so folder-scoped RLS works.
```sql
insert into storage.buckets (id, name, public)
  values ('avatars','avatars', true) on conflict (id) do nothing;
create policy "avatars_insert_own" on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "avatars_update_own" on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "avatars_read" on storage.objects for select
  using (bucket_id = 'avatars');
```

### Client
- **`Storage.uploadAvatar(_ data:, userId:)`** — POST to
  `object/avatars/{userId}/avatar-{ts}.jpg`, return the public URL (mirrors
  `uploadEventImage`). `nil` on failure → caller proceeds without an avatar.
- **`ProfileAPI`** (new, alongside `CommunityAPI`):
  - `getMyProfile() async -> TownProfile?` — `GET town_profiles?select=*` (RLS
    scopes to the caller), first row.
  - `upsert(displayName:avatarUrl:interests:onboarded:) async throws` — POST with
    `Prefer: resolution=merge-duplicates`, body keyed by `user_id = auth.uid()`,
    `updated_at = now()`, `onboarded_at` set when finishing.
- **`TownProfile`** model in `Models.swift`: `userId, displayName, avatarUrl, interests, onboardedAt`.

### On-device mirror + hydration
- `UserDefaults` (`Interests`) remains the **synchronous** source for matching.
- Add `Interests.displayName` get/set (UserDefaults) for local name cache.
- On launch (post-auth), `ProfileAPI.getMyProfile()`: if it returns a row, hydrate
  `Interests.set(remote.interests)`, cache name, and if `onboarded_at != nil` set
  the local onboarded flag (so a reinstall/new device doesn't re-onboard).
- Onboarding never blocks on the network: local always commits; Supabase upsert is
  best-effort and idempotent, retried on next launch if it failed.

## 5. Motion & interaction

Aligns with the design skills (high-end-visual-design, impeccable, emil-design-eng).

- **Photo card:** press → scale 0.97 spring; select → coral ring (3pt) scales in +
  checkmark circle (white check on coral) scales/fades in + subtle image zoom
  (1.0→1.04). Deselect reverses. Haptic `selection` on toggle.
- **Grid entrance:** cards fade + rise (stagger by index, capped) on first appear.
- **Continue pill:** disabled→enabled transitions with a spring; count label
  cross-fades ("Pick a few" → "Continue · 6").
- **Name:** field + caret focus on appear; button enables with spring; `submit`
  advances.
- **Avatar:** empty well breathes softly; on pick, image scales into the circle;
  uploading = subtle progress ring.
- **Progress bar:** active segment fills with `.easeInOut`; back reverses it.
- **Reduce Motion:** everything renders in final state — no stagger, no zoom, no
  pulse; haptics kept. Mirrors `MapIntroView.runIntro`'s guard.
- `Haptics.success()` on the final Continue into the map finale.

## 6. Accessibility
- Cards are one a11y element each: label + "selected"/"not selected" trait.
- Continue announces remaining count. Dynamic Type respected (labels scale, cards
  keep min tap target). VoiceOver order top-to-bottom per section.

## 7. DEBUG launch args (headless screenshot verification)
Extend `RootView` / `OnboardingView` to honor:
- `-onboarding-step name|interests|avatar` — start onboarding on a given step.
- `-onboarding-filled` — prefill a sample name + a few selected interests so the
  "filled" states screenshot without driving the UI.
Consistent with the app's existing `-open-tab`, `-explore-filter`, etc.

## 8. Verification
Per the repo discipline (no XCTest): **builds clean (0 warnings) + confirmed in the
simulator**. Screenshot loop each screen at each state:
- Name: empty, typed.
- Interests: none selected, several selected (ring + check + count), scrolled to a
  lower section.
- Avatar: empty well, image chosen.
- Progress bar + back across steps.
- Reduce-Motion pass renders correctly.
Record results in `MAP_BUILD_LOG.md` (onboarding subsection) as the app does for map work.

## 9. File-by-file change list
- `Hygge/Backend/Interests.swift` — new 18-item taxonomy + sections; add
  `displayName` get/set; keep `matches`, `get/set`, `isOnboarded` API.
- `Hygge/Backend/Models.swift` — `TownProfile`.
- `Hygge/Backend/ProfileAPI.swift` — **new** get/upsert.
- `Hygge/Backend/Storage.swift` — add `uploadAvatar`.
- `Hygge/Features/Onboarding/OnboardingView.swift` — new step machine, progress
  bar, back chevron; wire name/interests/avatar; Supabase upsert on finish.
- `Hygge/Features/Onboarding/InterestPickerView.swift` — **new** photo-card grid.
- `Hygge/Features/Onboarding/InterestCard.swift` — **new** card component + resolver.
- `Hygge/Features/Onboarding/NameStepView.swift` — **new**.
- `Hygge/Features/Onboarding/AvatarStepView.swift` — **new** (PhotosPicker).
- `Hygge/Features/Onboarding/OnboardingChrome.swift` — **new** progress bar + back.
- `Hygge/Assets.xcassets/` — `interest-<id>` imagesets (18).
- `Hygge/App/RootView.swift` — hydrate profile on launch; DEBUG step args.
- Supabase — `town_profiles` table + `avatars` bucket + policies (via migration).
- `MAP_BUILD_LOG.md` — onboarding verification log.

## 10. Open questions / tunables
- Minimum interests to continue (default: 1, gentle). Bump to 3/5 if desired.
- Table name `town_profiles` (vs `community_profiles`) — cosmetic.
- Whether to reuse `event-images` bucket instead of a new `avatars` bucket —
  chose dedicated for clean separation.
