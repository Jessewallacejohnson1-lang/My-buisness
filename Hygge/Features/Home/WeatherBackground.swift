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

    /// Cache is intentionally never invalidated: at most six files (one per
    /// state), so a cached clip is reused forever. Replacing a clip in the
    /// bucket requires clearing the app's Caches directory.
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
    @State private var resolveTask: Task<Void, Never>?

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
        .onDisappear { visible = false; resolveTask?.cancel(); controller.pause() }
        .onChange(of: state) { _, _ in resolveAndPlay() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, visible { controller.play() } else { controller.pause() }
        }
    }

    private func resolveAndPlay() {
        resolveTask?.cancel()
        guard motionAllowed, let state else { clipURL = nil; return }
        resolveTask = Task {
            let url = await WeatherClipCache.shared.localURL(for: state)
            if Task.isCancelled { return }
            guard let url else { return }
            controller.load(url)
            clipURL = url
            if visible, scenePhase == .active { controller.play() }
        }
    }
}
