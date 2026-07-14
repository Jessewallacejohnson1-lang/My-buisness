# Save-to-map — design

**Date:** 2026-07-13
**Feature:** the map's retention loop — save any place, and it becomes a pin on your
personal map, synced across your devices and surviving reinstalls.
**Status:** approved (brainstorm), pending implementation plan.

Second milestone of the "map alive" roadmap (after the Living Basemap). Later
milestones — Notes-with-expiry, then Warmth/honest-counts — are **out of scope here**.

---

## 1. Goal & principles

Today "saving" a place is **device-local only** — `SavedStore.shared` is a
`Set<String>` in UserDefaults (`ExploreKit.swift:97`), shared between Explore cards
and the map. The map already renders a `.saved` pin state (`PinDisplay`, precedence
`selected > live > saved > rest`), but saves don't sync, don't survive a reinstall,
and there is no Town/Mine layer, no distinct saved treatment beyond an ink bookmark,
and no flight.

Save-to-map graduates that into the real retention loop:

- **One table**, personal-only. RLS own-row. No schema sprawl.
- **Offline-first** — a save never lags and the map works with no signal.
- **Quiet, on-brand** — saved is a recolored marker, not a badge/streak/game.
- **Never inflate** — no social counts this milestone (honest counts is a later item).
- Coral stays reserved for **live/tappable**; saved gets its own warm tint.

## 2. Decisions (from brainstorm)

| Question | Decision |
|---|---|
| What does "Mine" show? | **Any place you've saved** — curated spots *and* Explore places (parks/trails/venues), each a pin, including ones not on the default town map. |
| The save moment | **Context-aware flight** — saving from a list/Explore flies the map to the place; saving a pin you're already on just recolors it in place. |
| The saved mark | **No ornament.** The normal marker, tinted **honey / warm gold** (`Hue.honey`). Not coral (coral == live). |
| Town ⇄ Mine switch | **Three peers in the sheet: Today · Places · Mine.** Mine is first-class; choosing it recedes non-saved pins, frames the saved set, and lists them. |
| Data/sync model | **Offline-first cache over one table.** `SavedStore` stays the instant local source; write-through to Supabase; hydrate + merge on launch. |
| Scope | **Personal-only.** No "N neighbors saved this" (deferred to the honest-counts milestone). |

## 3. Data model — `saved_places`

```sql
create table public.saved_places (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users (id) on delete cascade,
  place_id   text not null,          -- "downtown" | google place_id | park slug …
  name       text not null,          -- captured at save-time
  category   text not null,          -- park | trail | venue | college | chapel | downtown | …
  lat        double precision not null,
  lng        double precision not null,
  created_at timestamptz not null default now(),
  unique (user_id, place_id)         -- re-saving is idempotent
);

alter table public.saved_places enable row level security;

create policy "own rows – select" on public.saved_places
  for select using (auth.uid() = user_id);
create policy "own rows – insert" on public.saved_places
  for insert with check (auth.uid() = user_id);
create policy "own rows – delete" on public.saved_places
  for delete using (auth.uid() = user_id);
-- (no update policy: saves are insert/delete only; a re-save is an upsert on the
--  unique key, an un-save is a delete.)
```

**Self-contained by design:** each row carries its own `name` + `lat/lng`, so the
**Mine layer renders with zero joins** — no `places` table, no runtime geocode. RLS
mirrors `town_profiles` (own-row). Applied as a migration; recorded in
`MAP_BUILD_LOG.md`. Not added to any realtime publication (personal data, no
cross-user push needed).

## 4. Sync architecture

### 4.1 `SavedPlace` value
A new value type replaces the bare id:
```swift
struct SavedPlace: Identifiable, Codable, Hashable {
    let id: String            // place_id (stable key)
    let name: String
    let category: String
    let lat: Double
    let lng: Double
    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lng) }
}
```

### 4.2 `SavedStore` evolves from ids → places
`SavedStore` keeps its role as the instant, observable local source, but holds
`[String: SavedPlace]` (persisted as JSON in UserDefaults under a new key, e.g.
`hygge.saved.places.v2`; the old `hygge.saved.ids` is read once for migration then
retired). Public surface stays close to today's:
- `isSaved(_ id: String) -> Bool`
- `place(_ id: String) -> SavedPlace?`
- `all: [SavedPlace]` (for the Mine list, sorted by `created_at`/save order)
- `toggle(_ place: SavedPlace)` — optimistic local flip, then write-through.

### 4.3 `SavedPlacesAPI`
A thin domain API over the existing hand-rolled `SupabaseHTTP` (no Supabase SDK),
alongside `ProfileAPI`:
- `list() async throws -> [SavedPlace]`
- `upsert(_ place: SavedPlace) async throws` (PostgREST `Prefer: resolution=ignore-duplicates` on the unique key — a re-save never changes `name`/coords, so an insert-ignore is correct and needs only the INSERT policy, no UPDATE policy)
- `delete(placeId: String) async throws`

All calls use `AuthStore.validAccessToken()`.

### 4.4 Lifecycle
- **Toggle:** `SavedStore.toggle` updates memory + UserDefaults immediately (UI never
  waits), then fires the matching `upsert`/`delete` in a detached task. A failed
  write is retried on next launch reconcile (the local state is the queue).
- **Hydrate on launch/auth:** after sign-in (in `RootView.hydrateIfNeeded()`, next to
  the Interests mirror), call `list()` and reconcile with local:
  - rows in server-not-local → add to local;
  - rows in local-not-server → `upsert` them (covers offline saves + the migration);
  - the union becomes the new local truth.
- **First-launch migration (one-time):** read legacy `hygge.saved.ids`; for each,
  resolve a `SavedPlace` (curated ids via `MapSpots`; known venues via
  `KnownVenues`). Resolved ones are folded into the store (and thus upserted on the
  next reconcile). Ids that can't resolve a coordinate are **kept in a local
  legacy-ids set** so Explore's bookmark still shows saved, but they don't appear as
  Mine pins. Delete the legacy key after a successful first reconcile.

## 5. The save payload change

`SaveBookmarkButton(id:)` becomes `SaveBookmarkButton(place: SavedPlace)`. Call sites
already have the data:
- **Explore cards** (`ExploreKit`/`ActivitiesView`) — park/trail/venue cards carry
  name, category, and a coordinate (from `KnownVenues`/`TrailServices`/Google Places).
- **Map sheet spot detail** (`MapSheet`) — a `Spot` has `name`, `category`,
  `coordinate`.

Only **places with a coordinate** are savable. Events are not saved (they use
reminders and live on the timeline); if an event surface ever exposes a save, it must
not produce a Mine pin.

## 6. Pins & the sheet

### 6.1 Saved pin = honey dot
- `PinDisplay.saved` renders the **normal marker tinted `Hue.honey`** — a *dot*, not
  an elevated badge. Drop the ink `bookmark.fill` mini-badge. Only `.live` (coral +
  pulse) and `.selected` (lift/badge) get the full overlay badge; `.saved` stays a
  recolored GeoJSON circle so a saved place reads as "yours" without shouting.
- Precedence is unchanged: `selected > live > saved > rest`. A saved∩live place is
  still coral while live, reverting to honey when the event ends.
- In **Town** mode, honey dots sit quietly among gray rest dots. In **Mine** mode,
  only honey dots remain, so they're prominent by absence of the rest.

### 6.2 Sheet: Today · Places · Mine
- The header's two-way coral toggle pill (`MapSheet.swift:405`) becomes a **3-segment
  control** (`SheetMode { case today, places, mine }`).
- **Mine** list: `SavedStore.all` as rows (name, category glyph, "saved" honey dot,
  distance), tapping a row selects the place + flies to it. Empty state:
  *"No saved places yet — tap the bookmark on any place to start your map."*
- Selecting **Mine** drives the map: non-saved **rest pins are hidden** (removed from
  the GeoJSON source for the Mine layer), **live pins stay** (a live happening is
  never hidden — it may reappear in coral even if unsaved), and the camera
  fit-bounds-frames the saved set (see §7). Leaving Mine restores the full map.

## 7. Flight animation

Mapbox camera ease, gentle (~1.0s, ease-in-out), via the existing map-view camera
API. Triggers:

| Trigger | Camera |
|---|---|
| Save from a list / Explore | fly to the place, then it settles to honey |
| Save a pin you're already on | **no move** — recolor in place |
| Open **Mine** | fit-bounds to frame all saved places (padding for chrome + sheet) |
| Tap a **Mine** row | fly to that place, select it |

- **Fit-bounds math:** compute a `CoordinateBounds` over the saved set; if a single
  saved place, fly to it at a sensible zoom; if none, no move. Padding keeps the
  floating top chrome + sheet clear.
- **Reduce Motion:** all flights become an **instant recenter** (no glide), matching
  the Living Basemap's Reduce-Motion discipline.

## 8. Verification

- **`swiftc` harness** (per the no-XCTest pattern) for the pure logic: `SavedPlace`
  JSON round-trip, the hydrate/reconcile merge (server∪local, dedupe on `place_id`),
  the legacy-id → coordinate resolution, and the fit-bounds bounds computation
  (assert against hand-checked coordinates). Pin `TimeZone`/inputs as usual.
- **Sim screenshots:** honey saved pins in Town mode; Mine mode (framed saved set,
  rest receded); the empty Mine state; a saved∩live place staying coral.
- **DEBUG flags:** extend `-map-save <placeid>` (already exists) to seed Mine;
  add `-map-sheet mine` to open the sheet on the Mine list headlessly.
- **Build bar:** 0 warnings; confirmed in the running simulator (project convention).

## 9. Out of scope / non-goals

- No social/aggregate counts ("N neighbors saved this") — honest-counts milestone.
- No notes/annotations on saved places — Notes-with-expiry milestone.
- No sharing a saved place / a saved-map to a neighbor (could reuse `ShareCenter`
  later; not now).
- No `places` catalogue table — saves are self-contained.
- No realtime subscription on `saved_places` (personal, no cross-device push beyond
  launch hydrate).

## 10. Risks & mitigations

- **Coordinate for Explore saves.** Every savable Explore card must expose a real
  coordinate at save-time. Mitigation: `SaveBookmarkButton(place:)` won't compile
  without one; audit each call site during implementation.
- **Merge-up correctness.** Legacy local ids without resolvable coords must not
  silently vanish from Explore. Mitigation: keep them in a local legacy-ids set so the
  Explore bookmark still reflects saved; only Mine pins require coords.
- **Dropping the saved badge** could make Town-mode saves subtle. Accepted by design
  (quiet > shouty); Mine mode is where saved places take the stage.
- **Write-through failures** must never lose a save. Mitigation: local state is the
  durable queue; reconcile upserts local-only rows on every launch.
