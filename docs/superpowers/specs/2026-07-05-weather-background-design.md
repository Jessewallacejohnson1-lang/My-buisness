# WeatherBackground — looping video backdrop for the Today weather bar

**Date:** 2026-07-05
**Repo:** Block Party (native SwiftUI + Mapbox iOS app — *not* the Expo repo)
**Status:** Approved for planning

## Summary

Upgrade the Today tab's existing `WeatherBar` so its backdrop is a **looping,
muted video** matched to current conditions, instead of a static bundled photo.
The video is one of six state clips streamed/cached from a public Supabase
Storage bucket. While a clip is loading, unavailable, or motion is reduced, the
bar shows a **matched static gradient** so it never looks broken.

The original request was written in Expo / React Native terms (`expo-video`,
`expo-file-system`, `pointerEvents`, gradient fallback). This is the **native
iOS codebase**, so the spec translates those to their SwiftUI / AVFoundation /
FileManager equivalents. The RN/web version lives in the other repo and is out
of scope here.

## Decisions (locked)

1. **Evolve `WeatherBar` in place.** Add a `WeatherBackground` subview that
   replaces the `PhotoView` backdrop. Keep `WeatherBar`'s Open-Meteo fetch,
   label, temperature, and H/L overlay as-is. `WeatherBar`'s public API does not
   change, so `HomeView` is untouched.
2. **Clips are not uploaded yet.** Build the full download/cache pipeline so the
   bar degrades gracefully to the matched gradient today, and video lights up
   automatically once the six `.mp4`s land in the bucket.
3. **Honor Reduce Motion / Low Power Mode.** In either case, show the matched
   gradient and do not download or play video. Calmer, saves battery, on-brand.

## Non-goals / YAGNI

- No new tab-focus plumbing: the tab shell already removes `HomeView` from the
  tree on tab switch, so `.onDisappear` covers "pause when not focused."
- Not pausing the loop when the global "+" compose sheet is presented over Home
  — that's still the Today tab, the video is mostly hidden behind the sheet, and
  the cost is negligible. Explicitly out of scope.
- No persisted-across-launch weather cache. The 30-minute cache is in-memory
  (process lifetime), which satisfies "cache for 30 minutes" without serving
  stale conditions after a relaunch.
- No bundled-photo fallback tier. The gradient is the single fallback.

## Architecture

One new file — `BlockParty/Features/Home/WeatherBackground.swift` — plus small edits
to `BlockParty/Features/Home/WeatherBar.swift`.

### 1. `WeatherState` — the six states

An enum whose `rawValue` **is** the clip base name (matches the bucket filename
without extension):

```
clear-day · clear-night · cloudy · rain · snow · storm
```

One mapper, `WeatherState.from(code:isDay:)`, using WMO codes:

| WMO code | State |
|---|---|
| 0 clear | `clear-day` / `clear-night` (by `is_day`) |
| 1, 2 partly cloudy · 3 overcast · **45, 48 fog** | `cloudy` |
| **51–57 drizzle** · 61–67 rain · 80–82 rain showers | `rain` |
| 71–77 snow · 85, 86 snow showers | `snow` |
| 95, 96, 99 thunderstorm | `storm` |
| anything else | nearest → `clear-day` / `clear-night` |

Fog → cloudy and drizzle → rain per the request. Each state also carries a
**matched gradient** (2–3 sky-colored stops). These are bespoke colors: sky
tints are not covered by a `Hue` token, so — like the map's three allowed
base-map cartography hexes — they are defined here rather than as scattered
ad-hoc hexes. Proposed stops (tunable):

- `clear-day`: soft blue → pale blue
- `clear-night`: deep indigo → slate
- `cloudy`: muted grey-blue → light grey
- `rain`: cool slate (darker)
- `snow`: pale grey-white
- `storm`: dark charcoal-violet

### 2. `WeatherClipCache` (actor)

Resolves a `WeatherState` → local file URL.

- Target path: `Caches/weather-loops/<name>.mp4`.
- If the file exists, return it.
- Otherwise download from the public bucket
  `SupabaseConfig.url/storage/v1/object/public/weather-loops/<name>.mp4`
  (no auth header — public bucket, mirrors `Storage.swift`) to a temp file, then
  **atomically move** it into place. Return the local URL.
- **Coalesce** concurrent requests for the same state through one in-flight task.
- **Return `nil` on any failure** (404, offline, partial download). The caller
  then simply stays on the gradient. This is why "not uploaded yet" is safe.

### 3. `WeatherVideoController` + `AVPlayerLayer` host

- `AVQueuePlayer` + `AVPlayerLooper` for a **seamless muted loop**
  (`isMuted = true`, `actionAtItemEnd = .none`).
- A small `UIView` subclass with `layerClass = AVPlayerLayer` and
  `videoGravity = .resizeAspectFill` for **cover fit**; the layer auto-resizes
  with the view (no manual frame syncing / KVO).
- `load(url:)`, `play()`, `pause()` exposed to the SwiftUI layer.

### 4. `WeatherBackground` view (the backdrop)

Layered bottom → top:

1. **Matched gradient** — always present, so the bar is never empty.
2. **Looping video** — shown only when a cached clip URL exists *and* motion is
   allowed; fades in over the gradient so there's no pop or empty flash.

The whole view is `.allowsHitTesting(false)` (the `pointerEvents:"none"`
equivalent). Lifecycle:

- `.onAppear` → play · `.onDisappear` → pause. Because `MainTabsView` `switch`es
  on the selected tab, leaving "Today" removes `HomeView` from the tree, so this
  is exactly "pause when the Today tab isn't focused."
- `@Environment(\.scenePhase)` → pause when `!= .active` (app backgrounded).
- `accessibilityReduceMotion` **or** `ProcessInfo.processInfo.isLowPowerModeEnabled`
  → gradient only; the clip is never downloaded or played.
- On `state` change → resolve the clip via `WeatherClipCache`, load it into the
  controller, and play if currently focused.

### 5. `WeatherBar` edits

- `Weather` gains `let state: WeatherState`, computed alongside the existing
  `describe(code:isDay:)` label.
- `WeatherService.current()` gains a **30-minute in-memory cache** (currently it
  refetches on every `.task`).
- Replace the `PhotoView(name:)` backdrop with
  `WeatherBackground(state: weather?.state)`.
- Keep the existing bottom dark-fade gradient (`[.clear, black 0.45]`) and the
  temp/label overlay exactly as they are. That gradient already provides the
  "soft dark fade so the temperature stays readable" and sits above the video —
  no second fade is added.

## Data flow

```
WeatherBar.task
  └─ WeatherService.current()        // 30-min in-memory cache
       └─ Open-Meteo fetch → Weather { tempF, high, low, label, state }
            └─ WeatherBar renders WeatherBackground(state:)
                 ├─ gradient (always)
                 └─ WeatherClipCache.localURL(for: state)   // download+cache or nil
                      └─ WeatherVideoController → AVPlayerLayer (loop, muted, cover)
```

## Error handling / edge cases

- **Weather fetch fails** → `weather == nil` → default gradient; `WeatherBar`
  already shows "—" and no fake temperature.
- **Download fails / offline / bucket empty** → gradient only; retried on the
  next state change or next appearance.
- **Reduce Motion / Low Power** → gradient only, no network for video.
- **Partial/corrupt download** → download to temp, move into place only on
  success; an `AVPlayerItem` failure leaves the gradient in place.

## Verification

No XCTest target exists. "Verified" = **builds clean (0 warnings)** + confirmed
in the running simulator via screenshot, per `MAP_BUILD_LOG.md` discipline.

Because the bucket is empty today, the pass criteria are:

1. The bar shows the **matched gradient** with the live temperature overlay —
   not a broken/empty box.
2. Switching tabs and backgrounding the app do not crash and do pause playback.

Optionally, to prove the video path plays end to end, temporarily point one
state at a known-good public sample `.mp4`, screenshot the loop, then revert.
