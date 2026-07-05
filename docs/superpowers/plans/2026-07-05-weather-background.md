# WeatherBackground Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Today tab weather bar's static-photo backdrop with a looping, muted, cover-fit video matched to current conditions, cached locally, degrading to a matched gradient whenever the clip is loading/unavailable or motion is reduced.

**Architecture:** One new self-contained file (`WeatherBackground.swift`) holds a six-case `WeatherState`, an actor that downloads+caches clips from the public `weather-loops` Supabase bucket, an `AVQueuePlayer`/`AVPlayerLooper` controller behind an `AVPlayerLayer` host, and the composed backdrop view. `WeatherBar.swift` is edited to compute the state, cache the Open-Meteo result for 30 min, and swap `PhotoView` for `WeatherBackground`. `HomeView` is untouched.

**Tech Stack:** SwiftUI, AVFoundation (`AVQueuePlayer` + `AVPlayerLooper` + `AVPlayerLayer`), `URLSession` download, `FileManager` Caches directory. No new SPM dependency.

## Global Constraints

- **Deployment target iOS 26.5, Swift 5** — `onChange(of:) { _, _ in }` two-param signature and `URLSession.download(from:)` async are available.
- **No XCTest target.** "Verified" = builds clean with **0 warnings** + confirmed in the running simulator via screenshot (per `MAP_BUILD_LOG.md` discipline). The per-task cycle below is build → (screenshot for visible tasks) → commit.
- **Prefer XcodeBuildMCP** (`build_sim`, `build_run_sim`, `screenshot`) over raw `xcodebuild`. Scheme `Hygge`, bundle id `Jesse.Hygge`, simulator `iPhone 17`.
- **File-system-synchronized Xcode group:** new files under `Hygge/` are auto-included — no `.pbxproj` edit needed. After any build failure mentioning "Multiple commands produce", run `find Hygge -type d -name .impeccable -exec rm -rf {} +`.
- **Honest data only / on-brand:** never a fabricated temperature; coral (`Hue.accent`) is reserved for live/tappable and must not appear in this backdrop; don't hardcode a hex a `Hue` token already covers (the six sky gradients are the sanctioned exception, like the map's base-map hexes).
- **Public bucket, no auth:** clip URLs are `SupabaseConfig.url/storage/v1/object/public/weather-loops/<name>.mp4`, mirroring `Storage.swift`'s public-URL construction.
- The six clip base names are exactly: `clear-day`, `clear-night`, `cloudy`, `rain`, `snow`, `storm`.

---

### Task 1: `WeatherState` — six states, mapping, matched gradients

**Files:**
- Create: `Hygge/Features/Home/WeatherBackground.swift`

**Interfaces:**
- Produces: `enum WeatherState: String, CaseIterable` with `rawValue` == clip base name; `static func from(code: Int, isDay: Bool) -> WeatherState`; `var gradient: [Color]` (2 stops, top→bottom).

- [ ] **Step 1: Create the file with the state enum**

```swift
//
//  WeatherBackground.swift
//  Hygge — looping video backdrop for the Today weather bar.
//
//  Six weather-state clips live in the public `weather-loops` Supabase bucket
//  (clear-day.mp4 … storm.mp4). On first use a clip is downloaded to the Caches
//  directory and played from there after. While a clip is loading, missing, or
//  motion is reduced, a matched static gradient shows so the bar never looks
//  broken. Muted, looping, cover-fit, non-interactive; pauses when the Today
//  tab isn't focused or the app is backgrounded.
//
//  Native SwiftUI/AVFoundation port of the Expo spec (expo-video +
//  expo-file-system). See docs/superpowers/specs/2026-07-05-weather-background-design.md.
//

import SwiftUI
import AVFoundation

// MARK: - State

enum WeatherState: String, CaseIterable {
    case clearDay   = "clear-day"
    case clearNight = "clear-night"
    case cloudy
    case rain
    case snow
    case storm

    /// Open-Meteo WMO code + day flag → state. Fog → cloudy, drizzle → rain,
    /// unknown → nearest clear.
    static func from(code: Int, isDay: Bool) -> WeatherState {
        switch code {
        case 0:                return isDay ? .clearDay : .clearNight
        case 1, 2, 3, 45, 48:  return .cloudy
        case 51...67, 80...82: return .rain
        case 71...77, 85, 86:  return .snow
        case 95, 96, 99:       return .storm
        default:               return isDay ? .clearDay : .clearNight
        }
    }

    /// Two sky-toned stops (top → bottom). Bespoke colors: sky tints aren't a
    /// Hue token, so — like the map's allowed base-map hexes — they live here.
    var gradient: [Color] {
        switch self {
        case .clearDay:   return [Color(hex: 0x6FB4E8), Color(hex: 0xBFE0F5)]
        case .clearNight: return [Color(hex: 0x1B2A4A), Color(hex: 0x33415E)]
        case .cloudy:     return [Color(hex: 0x8A97A6), Color(hex: 0xB9C2CC)]
        case .rain:       return [Color(hex: 0x4E5A66), Color(hex: 0x74818C)]
        case .snow:       return [Color(hex: 0xAEB8C2), Color(hex: 0xDDE4EA)]
        case .storm:      return [Color(hex: 0x2C2E3A), Color(hex: 0x4A4E63)]
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles clean**

Run (XcodeBuildMCP): `build_sim` — scheme `Hygge`, simulator `iPhone 17`.
Expected: **BUILD SUCCEEDED, 0 warnings.** (`Color(hex:)` resolves via the extension in `HyggeColor.swift`.)

- [ ] **Step 3: Commit**

```bash
git add Hygge/Features/Home/WeatherBackground.swift
git commit -m "feat(weather): WeatherState enum with WMO mapping + matched gradients"
```

---

### Task 2: `WeatherClipCache` — download + local cache

**Files:**
- Modify: `Hygge/Features/Home/WeatherBackground.swift` (append)

**Interfaces:**
- Consumes: `WeatherState` (Task 1), `SupabaseConfig.url`.
- Produces: `actor WeatherClipCache` with `static let shared` and `func localURL(for state: WeatherState) async -> URL?` (nil on any failure; concurrent requests for the same state coalesced).

- [ ] **Step 1: Append the cache actor after the `WeatherState` enum**

```swift
// MARK: - Clip cache

/// Resolves a weather state to a local, playable clip URL: returns the cached
/// file if present, otherwise downloads it once from the public bucket (dupes
/// coalesced) and caches it. Returns nil on any failure — the caller then
/// simply stays on the gradient.
actor WeatherClipCache {
    static let shared = WeatherClipCache()

    private var inFlight: [WeatherState: Task<URL?, Never>] = [:]

    private var folder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("weather-loops", isDirectory: true)
    }

    private func remoteURL(for state: WeatherState) -> URL {
        SupabaseConfig.url
            .appendingPathComponent("storage/v1/object/public/weather-loops/\(state.rawValue).mp4")
    }

    func localURL(for state: WeatherState) async -> URL? {
        let dest = folder.appendingPathComponent("\(state.rawValue).mp4")
        if FileManager.default.fileExists(atPath: dest.path) { return dest }
        if let task = inFlight[state] { return await task.value }

        let remote = remoteURL(for: state)
        let dir = folder
        let task = Task<URL?, Never> {
            do {
                let (tmp, resp) = try await URLSession.shared.download(from: remote)
                guard let code = (resp as? HTTPURLResponse)?.statusCode,
                      (200..<300).contains(code) else { return nil }
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.moveItem(at: tmp, to: dest)
                return dest
            } catch {
                return nil
            }
        }
        inFlight[state] = task
        let result = await task.value
        inFlight[state] = nil
        return result
    }
}
```

- [ ] **Step 2: Build to verify it compiles clean**

Run: `build_sim` (scheme `Hygge`, `iPhone 17`).
Expected: **BUILD SUCCEEDED, 0 warnings.**

- [ ] **Step 3: Commit**

```bash
git add Hygge/Features/Home/WeatherBackground.swift
git commit -m "feat(weather): WeatherClipCache — download + cache clips, nil on failure"
```

---

### Task 3: `WeatherVideoController` + `AVPlayerLayer` host

**Files:**
- Modify: `Hygge/Features/Home/WeatherBackground.swift` (append)

**Interfaces:**
- Produces: `@MainActor final class WeatherVideoController` exposing `let player: AVQueuePlayer`, `func load(_ url: URL)`, `func play()`, `func pause()`; `struct PlayerLayerView: UIViewRepresentable` (init `player: AVPlayer`); `final class PlayerHostView: UIView`.

- [ ] **Step 1: Append the controller and host view after the cache actor**

```swift
// MARK: - Player

/// Owns a seamless, muted loop for one clip. `load` fully resets before
/// re-looping so switching states never stacks players.
@MainActor
final class WeatherVideoController {
    let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?

    init() {
        player.isMuted = true
        player.actionAtItemEnd = .none
        player.preventsDisplaySleepDuringVideoPlayback = false
    }

    func load(_ url: URL) {
        looper = nil
        player.removeAllItems()
        let item = AVPlayerItem(url: url)
        looper = AVPlayerLooper(player: player, templateItem: item)
    }

    func play() { player.play() }
    func pause() { player.pause() }
}

/// Hosts an AVPlayerLayer that cover-fills and auto-resizes with the view — no
/// manual frame syncing because the layer *is* the view's backing layer.
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerHostView {
        let view = PlayerHostView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PlayerHostView, context: Context) {
        if view.playerLayer.player !== player {
            view.playerLayer.player = player
        }
    }
}

final class PlayerHostView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
```

- [ ] **Step 2: Build to verify it compiles clean**

Run: `build_sim` (scheme `Hygge`, `iPhone 17`).
Expected: **BUILD SUCCEEDED, 0 warnings.**

- [ ] **Step 3: Commit**

```bash
git add Hygge/Features/Home/WeatherBackground.swift
git commit -m "feat(weather): looping muted AVPlayer controller + AVPlayerLayer host"
```

---

### Task 4: `WeatherBackground` — composed backdrop with lifecycle

**Files:**
- Modify: `Hygge/Features/Home/WeatherBackground.swift` (append)

**Interfaces:**
- Consumes: `WeatherState`, `WeatherClipCache.shared`, `WeatherVideoController`, `PlayerLayerView` (Tasks 1–3).
- Produces: `struct WeatherBackground: View` with `init(state: WeatherState?)`.

- [ ] **Step 1: Append the backdrop view**

```swift
// MARK: - Backdrop

/// Matched-gradient backdrop that upgrades to a looping muted video when a clip
/// is available and motion is allowed. Non-interactive (pointerEvents:"none");
/// pauses off-screen and when the app is backgrounded.
struct WeatherBackground: View {
    let state: WeatherState?

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var controller = WeatherVideoController()
    @State private var clipURL: URL?
    @State private var visible = false

    /// Which gradient to show — default to a calm clear-day sky before the first
    /// fetch resolves, so the bar is never empty.
    private var displayState: WeatherState { state ?? .clearDay }

    /// Reduce Motion or Low Power Mode → gradient only; never download or play.
    private var motionAllowed: Bool {
        !reduceMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: displayState.gradient, startPoint: .top, endPoint: .bottom)

            if let clipURL, motionAllowed {
                PlayerLayerView(player: controller.player)
                    .id(clipURL)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: clipURL)
        .allowsHitTesting(false)
        .onAppear { visible = true; resolveAndPlay() }
        .onDisappear { visible = false; controller.pause() }
        .onChange(of: state) { _, _ in resolveAndPlay() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, visible { controller.play() } else { controller.pause() }
        }
    }

    private func resolveAndPlay() {
        guard motionAllowed, let state else { clipURL = nil; return }
        Task {
            guard let url = await WeatherClipCache.shared.localURL(for: state) else { return }
            controller.load(url)
            clipURL = url
            if visible, scenePhase == .active { controller.play() }
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles clean**

Run: `build_sim` (scheme `Hygge`, `iPhone 17`).
Expected: **BUILD SUCCEEDED, 0 warnings.** (`onChange(of: state)` compiles because `WeatherState?` is `Equatable` via its `String` raw value.)

- [ ] **Step 3: Commit**

```bash
git add Hygge/Features/Home/WeatherBackground.swift
git commit -m "feat(weather): WeatherBackground — gradient + looping video, focus-aware"
```

---

### Task 5: Wire `WeatherBackground` into `WeatherBar` (state + 30-min cache + swap backdrop)

**Files:**
- Modify: `Hygge/Features/Home/WeatherBar.swift`

**Interfaces:**
- Consumes: `WeatherState.from(code:isDay:)`, `WeatherBackground(state:)`.
- Produces: `Weather` gains `let state: WeatherState`; `WeatherService.current()` gains a 30-min in-memory cache; `WeatherService.label(code:isDay:)` replaces `describe`.

- [ ] **Step 1: Replace the `Weather` struct and `WeatherService` enum**

Replace the current `struct Weather { … }` and `enum WeatherService { … }` (lines 13–62) with:

```swift
struct Weather {
    let tempF: Int
    let highF: Int
    let lowF: Int
    let label: String
    let state: WeatherState
}

// MARK: - Service (open-meteo, St. Joseph, MN)

enum WeatherService {
    private static var cached: (weather: Weather, at: Date)?
    private static let ttl: TimeInterval = 30 * 60  // 30 minutes

    static func current() async -> Weather? {
        if let c = cached, Date().timeIntervalSince(c.at) < ttl { return c.weather }

        let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=45.565&longitude=-94.3186&current=temperature_2m,weather_code,is_day&daily=temperature_2m_max,temperature_2m_min&temperature_unit=fahrenheit&timezone=America%2FChicago&forecast_days=1")!
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let r = try JSONDecoder().decode(Response.self, from: data)
            let isDay = r.current.is_day == 1
            let weather = Weather(
                tempF: Int(r.current.temperature_2m.rounded()),
                highF: Int((r.daily.temperature_2m_max.first ?? r.current.temperature_2m).rounded()),
                lowF: Int((r.daily.temperature_2m_min.first ?? r.current.temperature_2m).rounded()),
                label: label(code: r.current.weather_code, isDay: isDay),
                state: WeatherState.from(code: r.current.weather_code, isDay: isDay)
            )
            cached = (weather, Date())
            return weather
        } catch {
            return cached?.weather   // last real reading, or nil — never a fake number
        }
    }

    private struct Response: Decodable {
        struct Current: Decodable { let temperature_2m: Double; let weather_code: Int; let is_day: Int }
        struct Daily: Decodable { let temperature_2m_max: [Double]; let temperature_2m_min: [Double] }
        let current: Current
        let daily: Daily
    }

    /// WMO weather code → human label (day-aware).
    static func label(code: Int, isDay: Bool) -> String {
        switch code {
        case 0:                return isDay ? "Clear" : "Clear night"
        case 1, 2:             return "Partly cloudy"
        case 3:                return "Overcast"
        case 45, 48:           return "Foggy"
        case 51...67, 80...82: return "Rain"
        case 71...77, 85, 86:  return "Snow"
        case 95, 96, 99:       return "Storms"
        default:               return isDay ? "Clear" : "Clear night"
        }
    }
}
```

- [ ] **Step 2: Swap the backdrop and drop the photo/drift state in `WeatherBar`**

Replace the entire `struct WeatherBar: View { … }` with:

```swift
struct WeatherBar: View {
    @State private var weather: Weather?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            WeatherBackground(state: weather?.state)
                .frame(height: 132)
                .frame(maxWidth: .infinity)
                .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.45)],
                startPoint: .top, endPoint: .bottom
            )

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("St. Joseph, Minnesota")
                        .font(.sansSemibold(14))
                        .foregroundStyle(.white)
                    Text(weather?.label ?? "—")
                        .font(.sans(12))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                if let w = weather {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(w.tempF)°")
                            .font(.monoMedium(30))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                        Text("H \(w.highF)°  L \(w.lowF)°")
                            .font(.mono(11))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
            .padding(14)
            .shadow(color: .black.opacity(0.3), radius: 8, y: 1)
        }
        .frame(height: 132)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Hue.hairline, lineWidth: 1))
        .task { weather = await WeatherService.current() }
    }
}
```

This drops the now-unused `@Environment(\.accessibilityReduceMotion)`, `@State private var drift`, `photoName`, `PhotoView`, and the drift `.onAppear` — `WeatherBackground` owns motion now. `PhotoView`/`Photo` stay defined in `BundleImage.swift` (still used by the around-town carousel).

- [ ] **Step 3: Build clean**

Run: `build_sim` (scheme `Hygge`, `iPhone 17`).
Expected: **BUILD SUCCEEDED, 0 warnings.**

- [ ] **Step 4: Run in the simulator and screenshot the Today tab**

Run: `build_run_sim` (scheme `Hygge`, `iPhone 17`), then `screenshot`.
Expected: the weather bar shows a **matched gradient** (the `weather-loops` bucket is empty today, so no video yet) with the live temperature, label, and H/L overlaid and readable over the bottom fade — **not** a blank/broken box. The gradient tone matches the current condition/day (e.g. blue by day, indigo at night).

- [ ] **Step 5: Verify focus/background pausing doesn't crash**

Switch to the Map tab and back (`build_run_sim` then drive, or launch with `-open-tab map` and switch), and background/foreground the app. Expected: no crash; on return the bar re-renders normally. (Because `MainTabsView` `switch`es on tab, leaving Today deallocates `HomeView`, so `.onDisappear` pauses; `scenePhase` covers backgrounding.)

- [ ] **Step 6 (optional smoke test — prove the video path, then revert):** Temporarily change `WeatherClipCache.remoteURL` (or drop one `<name>.mp4` into `Caches/weather-loops/`) to point one state at a known-good small public `.mp4`. `build_run_sim` + `screenshot` the Today tab and confirm the loop plays, cover-fit, muted, corners clipped, temp still readable. **Revert the change** before committing.

- [ ] **Step 7: Commit**

```bash
git add Hygge/Features/Home/WeatherBar.swift
git commit -m "feat(weather): swap WeatherBar photo backdrop for WeatherBackground video + 30-min cache"
```

---

## Self-Review

**1. Spec coverage:**
- Open-Meteo fetch → `WeatherService.current()` (unchanged URL). ✓
- 30-min cache → Task 5 `cached`/`ttl`. ✓
- Six-state mapping incl. fog→cloudy, drizzle→rain, else→nearest → `WeatherState.from` (Task 1). ✓
- Looping muted video, cover fit, clipped to rounded corners, pointerEvents none → Tasks 3–5 (`AVPlayerLooper`, `isMuted`, `.resizeAspectFill`, `WeatherBar.clipShape`, `.allowsHitTesting(false)`). ✓
- Clips in public `weather-loops`, download on first use + cache locally, play from cache → `WeatherClipCache` (Task 2). ✓
- Gradient fallback while loading/offline → `WeatherBackground` always renders the gradient (Task 4). ✓
- Soft dark fade at bottom for legibility → existing `[.clear, black 0.45]` gradient kept above the video (Task 5). ✓
- Pause when Today tab not focused → `.onDisappear`/`.onAppear` + `scenePhase` (Task 4). ✓
- Reduce Motion / Low Power → gradient only (`motionAllowed`, Task 4). ✓

**2. Placeholder scan:** No TBD/TODO; every code step is complete. The only optional/unspecified item is Task 5 Step 6's sample `.mp4` URL, intentionally left to the executor and explicitly reverted. ✓

**3. Type consistency:** `WeatherState.from(code:isDay:)`, `WeatherState.gradient`, `WeatherClipCache.shared.localURL(for:)`, `WeatherVideoController.player/load/play/pause`, `PlayerLayerView(player:)`, `WeatherBackground(state:)`, `Weather.state`, `WeatherService.label(code:isDay:)` — names and signatures match across all tasks and consumers. ✓
