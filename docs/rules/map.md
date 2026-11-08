# The map

The map is presented, not tabbed. Read this before touching `Features/Map/`, a bubble, the
basemap, or the realtime pipeline behind it.

## Anatomy

Since the map reset (BP app `references/map-reset/`, 2026-10-30) the map shows today's events, plus
the one Event an Event page or a held Town card asked for, whatever its day (BP app inside-cards 19).

- **`SJMapView`** — raised as a `.fullScreenCover` from the Town bar's yellow disc, an Event page's
  small map, or a held Town card's View on Map (`EventMapOpener`), with its own close X. The cover sits
  on the shell's `NavigationStack`, outside it, so it rises over a pushed Event page and closing it lands
  back on that page as it was. The Mapbox map on one static basemap (`BasemapPalette`, Uber's colours), today's bubbles,
  and two glass circles: close top left, recenter top right, with `MapCompass` under recenter once
  the map is turned. One pill between them says "Nothing else today" once every one of today's
  events is over, or "You're offline" / "Couldn't load" (tap to try again). The Mapbox wordmark is
  hidden and its ⓘ attribution kept, top left under close, clear of the card (Jesse accepted the ToS
  risk, 2026-08-14). Its own
  `NavigationStack` pushes the Event page, so Back returns to the map; that page's small map pops back
  to the map instead of raising a second one.
- **An asked-for Event** (`EventMapOpener.Ask`, inside-cards 19) — the map opens over its spot 1.6 zoom
  steps out (`MapFocus.arriveFrom`) and flies in to the opening zoom with its bubble first to pop in and
  its card up (`MapFocus.arrive`), over or called off too. At a spot it shares with tonight's it leads the
  bubble and the card. Another day's tag says the day ("Thu, Nov 19") or "Until Dec 15" while one that
  began before today is still on (`TodayBubbleRules.dayTag`), and the card's time line says the same day.
  "Nothing else today" hides while a card is up. Asked for by its own page, a tap on its card closes the
  map. The card's Directions pill opens Apple Maps to the spot by its coordinate (`Directions.url(to:)`).
- **`MapModel`** (`@MainActor`) — today's events are the Town feed's own cards (`TownFeed`, read
  before the map opens), so the map shows what the Town feed shows, with the same hearts, Going,
  hides and mutes, and makes no second `get_town_feed` read (8 s for a new account, 2026-10-30).
  Their spots are `club_events.lat,lng` (`CommunityAPI.eventSpots`), read once per event. Every Event
  card carries the same spot, or `no_place` (Online, a bare town, several places), so an Event page's Map
  and a held card's View on Map act from the card alone (`EventMapRoute`), offline too. Follows
  the app's one `club_events` connection (`LiveGames.follow`, BP app codebase-health-2 08): a change
  touching today asks the Town feed to read again after 300 ms. `LiveGames.away` drops the
  connection in the background; the map re-reads on foreground and rolls over at midnight.
- **`TodayPlaces`** — one bubble per exact spot, its events ordered on-now first
  (`TodayBubbleRules.order`); events without a spot stay off. `merge` folds bubbles that touch on
  screen into one, run when the camera settles (`onMapIdle`).
- **`TodayBubbles`** — the shipped liquid-glass photo bubble (2026-10-23), drawn at 46 pt and scaled
  by the zoom: 36 pt zoomed out, 46 at the opening zoom (14.6), 72 two steps in. `MapZoom` carries
  the zoom so a pinch redraws only the bubbles; the time tag keeps its size.
- **`MapEventCard`** — Airbnb's map card, measured off Mobbin: photo, then title (with Now), place,
  time, and the friends Going, or else the going count. Heart and close on the photo; it pages
  through a bubble's events, opening on the first one friends are Going to.
- **Friends on the map** (BP app five-tabs 08) — a bubble shows friends Going to an Event there
  today: up to two 20 pt faces on its top right, then "+3". They come with the Town feed's cards,
  so a friend with "Show my plans to friends" off never shows. Going, never anyone's location.
- **Where an event is** — the morning job writes `club_events.lat,lng` from the source registry's
  hand-checked coordinates (`at:` per entry, `venue_at:` per named venue): the venue the event's
  location names, or its Place's own spot when the location is empty or names that Place. No real
  match stays empty and is listed in the morning report; the map leaves it off. Each morning
  re-checks every upcoming event and writes only what changed, so a moved event follows. An event
  posted in the app (posting is paused) gets its spot the next morning.

`MapSpots`, `KnownVenues`, `POI` and `POILogoCache` stay for Search, onboarding and the seeder; the
map no longer reads them for pins.

## Rules

- **Live is for *now*, not "today".** A bubble breathes only while its event is on (`EventWhen`:
  `end_at`, else two hours after the start). Called off, or a game whose final is in, it's over.
- **Realtime DELETE carries only the primary key.** A DELETE's `old_record` holds just `id`; match
  deletes by `id` (a full refetch is idempotent). `club_events` is `REPLICA IDENTITY FULL` and in the
  `supabase_realtime` publication.
- **Mapbox v11 `updateGeoJSONSource` does NOT throw — don't wrap it in `try?`.** A `try` around a
  non-throwing call is a warning, and the bar is 0 warnings. `addSource` / `addLayer` / `addImage`
  and `setCameraBounds` do throw: keep `try` with a logged `do/catch`.
- **The map is the SwiftUI `Map`, NOT the UIKit `MapView`.** `SJMapView` renders
  `Map(viewport: $viewport)` inside `MapReader { proxy in }` (`proxy.map` is the `MapboxMap`).
  Gestures are `.gestureOptions(...)`, the camera is the `viewport` binding animated with
  `withViewportAnimation`, 120 Hz is `.frameRate(range:preferred:)`, the pitch clamp is
  `setCameraBounds` in `.onStyleLoaded`. Map-specific modifiers must come before the standard ones
  (`.onChange` erases the `Map` type).
- **Per-frame camera values never go in the map view's `@State`.** `onCameraChanged` fires every
  frame: the bearing goes to `CompassHeading`, the zoom to `MapZoom`, each observed only by what
  draws it.
- **Don't re-enable Mapbox's built-in compass.** Its needle isn't ours and its tap levels the bearing
  only; `MapCompass` replaces it.
- **`docs/archive/MAP_BUILD_LOG.md`** is the archived record of map work up to 2026-09-27. Read it
  for history; commit messages are the record now.

## Direction — Jesse's calls

- 2026-10-30 — The map shows only today's events (2026-11-06, inside-cards 06 and 19: and the one Event
  its page asked for, any day), one bubble per real spot, Airbnb's card on a tap (Directions added),
  and only close and recenter for buttons; business pins, chips, search, help, the town pill and the
  bottom sheet are gone (map reset). **Supersedes** the pin states, Google categories, black cluster
  bubbles and the Flighty pin card below the line in the archive.
- Keep the light Mapbox style in Uber's colours. **Do not switch to satellite imagery.**
- References: Airbnb's map card (map reset), and the map-today bubble mock
  (`references/map-today/pulse.html`).
