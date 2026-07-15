# Living Basemap — design

> **RETIRED (2026-07-13).** The time/season/weather basemap recoloring this spec describes was
> built, then reversed the same day — the map now uses one static `BasemapPalette` matched to a
> Life360/Mobbin reference, no modulation. See the "Living Basemap retired" entry in
> `MAP_BUILD_LOG.md` for why and what replaced it. Kept here as a historical record.

**Date:** 2026-07-13
**Status:** Approved (brainstorm) → planning
**Scope:** This week's item only. Save-to-map, Notes-with-expiry, and Warmth/honest-counts are separate future specs; this document is laser-focused on the Living Basemap.

## Vision

> The map is alive before a single person touches it.

Open the town map at 4:15pm on a snowy January afternoon and it *is* that: a pale winter palette under a dusk wash, faint snow drifting, and a quiet line under the town pill that reads `❄ 38° · light snow · 4:15`. Open it at noon in July and it's bright, sage-green, and clear. No one has to post anything for the map to feel like St. Joseph, right now.

Three dimensions drive it — **time of day**, **season**, **weather** — composed into one value and read by everything downstream. Pure client-side. **No Supabase schema, no backend, no location permission.**

## Principles (inherited)

- **Coral is reserved.** `Hue.accent` marks live/tappable only. The weather whisper and all atmosphere chrome use neutral ink + muted tones — never coral.
- **Real only.** Weather is real (Open-Meteo); time and season are the device clock + St. Joe's coordinates. Nothing seeded.
- **Reduce Motion honored.** Every animated element (wash cross-fade, particles) has a static fallback, matching the existing `PulseRing` / share-reveal discipline.
- **Anchored to the town.** Atmosphere is computed for **St. Joseph's fixed coordinates**, independent of where the user pans. The town pill's *name* still follows the pan (existing behavior); the living ambience represents the app's home town. (Time/season are region-invariant; neighboring MN towns share weather — so this reads correct, not stale.)
- **Today's `MapPalette` is the anchor.** The current warm hexes are the *midday · clear · summer* baseline. Everything modulates around them; we never throw the tuned Life360 look away.

## The spine: `TownAtmosphere`

A single composed value every downstream unit reads:

```
TownAtmosphere {
    dayFactor: Double        // continuous 0 (deep night) → 1 (solar noon)
    phase: TimePhase         // .dawn .day .golden .dusk .night  (label + weather logic only)
    season: Season           // .winter .spring .summer .autumn  (+ blend edge)
    sky: SkyCondition        // .clear .cloudy .overcast .fog .rain .snow .storm
    tempF: Int?              // nil until weather resolves
    isDay: Bool
    resolvedAt: Date?        // nil = weather not yet loaded (offline/first frame)
}
```

**Critical sequencing — alive on the first frame, offline:**
1. On `start()`, `dayFactor`/`phase`/`season` are computed **synchronously on-device** → a v0 atmosphere publishes immediately (map is alive with zero network).
2. Cached weather (if fresh) fills `sky`/`tempF` instantly.
3. A background fetch refines `sky`/`tempF` a moment later; the map deepens without a jump.

## Components (one job per file, `Features/Map/Atmosphere/`)

### `SolarClock.swift` — time of day, offline
NOAA solar-position equations for St. Joe's latitude/longitude. Pure, deterministic, no network, no permission. This is what makes golden hour land at the *real* hour — St. Joe's sunset swings ~9:03pm (late June) → ~4:34pm (late Dec).

- `sunTimes(on: Date, at: Coord) -> (sunrise: Date, sunset: Date, solarNoon: Date)`
- `dayFactor(at: Date) -> Double` — continuous. ~0 well before sunrise / after sunset, ramps to 1.0 at solar noon. Drives smooth all-day palette + wash (no stepped snaps).
- `phase(at: Date) -> TimePhase` — golden window = within ~40 min of sunrise/sunset; dusk = sun just below horizon; night = fully down; day = otherwise. For labels/weather logic only.

### `SeasonClock.swift` — season, offline
- `season(on: Date) -> Season` + `blend: Double` toward the next season near boundaries, so autumn→winter eases rather than flips on a date. Northern hemisphere, meteorological seasons.

### `WeatherProvider.swift` — sky, real, swappable
```
protocol WeatherProvider {
    func current(at coord: Coord) async throws -> WeatherSnapshot
}
```
- `OpenMeteoWeatherProvider` — one `URLSession` GET, no key:
  `GET api.open-meteo.com/v1/forecast?latitude=45.5644&longitude=-94.3211&current=temperature_2m,weather_code,is_day&temperature_unit=fahrenheit&timezone=America/Chicago`
  Decodes one small struct. Maps **WMO weather_code → SkyCondition** (0 clear; 1–3 cloudy; 45/48 fog; 51–67 rain; 71–86 snow; 95–99 storm) with a light/moderate/heavy intensity read off the code band.
- `CachedWeatherProvider` — wraps any provider; persists the last `WeatherSnapshot` + timestamp in **UserDefaults** (`hygge.atmosphere.weather`), ~20-min TTL. Returns cache instantly, refreshes behind it, and serves stale cache when offline (never blanks the whisper).
- **WeatherKit seam:** a `WeatherKitWeatherProvider` conforming to the same protocol is the *only* change needed when Jesse's paid dev account lands — one file + one line in `AtmosphereModel` to switch. Documented in the file header.

### `BasemapPalette.swift` — atmosphere → Mapbox layer colors
Replaces the static `MapPalette`. `static func make(for: TownAtmosphere) -> BasemapPalette` returning `land / green / water / building` hexes + a `wash` spec. Modulation composes in HSB, **bounded** so it always stays tasteful:

1. **Season sets per-role anchors** (hand-tuned for control, not pure math):
   - Summer = today's palette (sage `#C9E0B4`, warm beige `#F0EBE3`, soft blue `#A6CBE6`, `#E8E4DC`).
   - Autumn = green→tawny/olive, land a touch warmer.
   - Winter = green→pale frost + desaturated, land cooler, water icy-grey, buildings cool.
   - Spring = green fresher/brighter, water clear.
   - Season `blend` lerps between adjacent anchors near boundaries.
2. **Time modulates brightness + warmth** off `dayFactor`: solar-noon = full/neutral; golden = slightly dimmer + amber warmth (hue→orange, +sat on land/buildings); dusk = dimmer + violet; **night = brightness ×~0.72, desaturate ~30%, water→deep slate-blue, land→cool slate** (moonlit, still WCAG-legible — never pure black).
3. **Sky adjusts**: overcast/fog desaturate + slightly flatten; **fresh snow** lifts land/green toward white in cold conditions; rain cools/darkens a touch.

All three are continuous functions → the map eases through the day. Bounds are specified as tunables the build refines against screenshots.

### `TimeWashOverlay.swift` — the atmospheric glow
A non-interactive full-field gradient above the map, **low opacity (≤ ~0.16)** so pins stay crisp (the palette — which sits *below* the pins — carries most of the time feel; the wash is a faint accent):
- Golden: warm gold (`~#FFB870`) top-trailing → clear.
- Dusk: indigo/rose → clear.
- Night: near-uniform indigo (`~#1B2440`) veil, the strongest (~0.14–0.18), multiply-leaning so it deepens.
- Day: ~0.
Opacity + tint interpolate off `dayFactor` with `.easeInOut`. `allowsHitTesting(false)`.

### `WeatherParticles.swift` — snow / rain, GPU-cheap
`Canvas` inside `TimelineView(.animation)`, non-interactive, above the map / below chrome. Only rendered for `.snow / .rain / .storm`:
- **Snow**: ≤ ~60 flakes, slow drift + horizontal sway, varied size/opacity, wraps vertically.
- **Rain**: ≤ ~80 streaks, faster, slight angle.
- Intensity (light/mod/heavy from WMO band) scales count + speed.
- **Fog/overcast get no particles** — handled as haze + desaturation in the palette/wash.
- **Reduce Motion → static** frame (a few settled flakes / faint haze; no `TimelineView`). Pauses on background (scenePhase).

### `AtmosphereWhisper.swift` — the quiet "why"
The town pill gains a second line. Pill becomes a VStack: line 1 = `📍 {town name}` (existing, pan-following); line 2 = `{glyph} {tempF}° · {condition} · {h:mm}`.
- Caption size (~12–13), `Hue.ink2`; glyph in a **muted condition/season tone, never coral**.
- Hidden until weather resolves — the pill expands the second line in with a gentle fade+slide (no layout jump); Reduce Motion = instant.
- Human condition text ("light snow", "overcast", "clear"). Temp °F. Time = current local `h:mm`.
- a11y: element label "Currently 38 degrees, light snow, 4:15 PM in Saint Joseph." Particles `accessibilityHidden`.

### `AtmosphereModel.swift` — `@MainActor ObservableObject`
Owns the composition. `@Published private(set) var current: TownAtmosphere`.
- `start()`: compute time+season synchronously → publish v0; load cached weather; kick a refresh.
- Recompute time on the existing 1-min heartbeat (reuse `MapModel`'s cadence or its own light timer) so `dayFactor`/`phase` stay live and the palette eases; season on start + midnight.
- Refresh weather every ~20 min foreground + on foreground if stale; back off/keep-stale on error.
- **DEBUG override:** parses `-atmosphere` (below) and, when present, freezes `current` to the forced mood — the live providers are bypassed so every combination is screenshot-verifiable.

`MapModel` stays events/realtime only — a clean seam; the two models are independent.

## Integration in `SJMapView`

- `@StateObject private var atmosphere = AtmosphereModel()`.
- Capture the `MapboxMap` (from `MapReader`'s proxy). `recolorBasemap` reads `BasemapPalette.make(for: atmosphere.current)` and is re-applied **both** on `.onStyleLoaded` **and** on `.onChange(of: atmosphere.current)` (the palette currently only applies once — this is the key wiring change).
- Add `TimeWashOverlay(atmosphere:)` and `WeatherParticles(atmosphere:)` into the ZStack, above `mapLayer`, below `topChrome`/`floatingControls`/`MapSheet`.
- `townPill` embeds `AtmosphereWhisper(atmosphere:)`.
- `.onAppear { atmosphere.start() }`; refresh on `scenePhase == .active`.

**Palette cross-fade (polish):** on a weather-condition change, animate wash + whisper (SwiftUI). Basemap hex interpolation over ~0.8s is a *nice-to-have* — degrade to an instant set if it costs frames (phase deltas every minute are already imperceptible, so snaps are rare during a session).

## Accessibility & performance

- Pins + labels must stay WCAG-legible in **every** mood (verify night + overcast specifically). This bounds how dark night can go.
- Reduce Motion: no particle animation, no wash cross-fade, instant palette.
- Cost: solar/season are trivial math; one small weather GET / 20 min (cached); layer-color sets are cheap at 1-min cadence; particles only during real precip, capped, paused off-screen. No continuous animation on a clear day.

## Verification

DEBUG launch arg forces any mood headlessly (mirrors the project's existing `-open-tab` / `-almanac-write` pattern):

```
-atmosphere season:winter,phase:night,sky:snow,temp:38   # or daylight:0.0 to force dayFactor
```

Keys: `season:`, `phase:`, `sky:`, `temp:`, `daylight:` (0–1 dayFactor override). Any subset; unspecified fields fall back to live/computed.

**Screenshot matrix:** summer·day·clear, autumn·golden·clear, winter·night·snow, spring·dawn·rain, day·overcast·fog. Plus a **montage** (record → frames → contact sheet) for snow drift + the golden→night wash cross-fade, per the project's established motion-verification loop. Build must be **0 warnings** and confirmed in the running simulator.

## Non-goals (YAGNI)

- No hourly forecast, no precipitation radar, no "tomorrow."
- No per-pan weather re-fetch (atmosphere is anchored to St. Joe).
- No new Supabase table, RLS, or edge function.
- No CLLocation / location-permission prompt.

## WeatherKit transfer checklist (later, when the paid dev account lands)

1. Add `WeatherKitWeatherProvider: WeatherProvider` (maps `WeatherKit` conditions → `SkyCondition`).
2. Switch the provider in `AtmosphereModel` (one line).
3. Add the WeatherKit capability + entitlement; add the required " Weather" attribution near the whisper.
No other file changes.
