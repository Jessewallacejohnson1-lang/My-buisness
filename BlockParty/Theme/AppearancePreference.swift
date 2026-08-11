//
//  AppearancePreference.swift
//  Block Party — which appearance the neighbour asked for.
//
//  Dark mode landed app-wide when every `Hue` token became dynamic and `RootView`
//  stopped pinning `.light`. That left the app following the phone with no way to
//  disagree. This is the disagreement: three states, persisted, applied at the root.
//
//  THREE STATES, AND `.system` IS NOT `.light`. `.system` means "follow the phone"
//  and maps to `nil` — the absence of a request. `.light` and `.dark` are requests.
//  Collapsing the two would silently pin the app to light for everyone who never
//  opened the menu, which is exactly the bug the dark-mode work just removed.
//
//  APPLIED WITH `.preferredColorScheme`, NEVER `.environment(\.colorScheme, …)`.
//  The environment key FORCES a value down the view tree and does not reach UIKit —
//  the glass surfaces (tab bar, map sheet) and any presented sheet would keep
//  resolving the device's appearance while everything drawn on them flipped. The
//  preference REQUESTS a scheme of the enclosing presentation, which is what turns
//  the hosting window's interface style over and takes the whole tree with it.
//  See the note at the old call site in `RootView`.
//

import SwiftUI
import UIKit
import Combine

/// System / Light / Dark, as stored and as spoken.
///
/// `nonisolated` (the module defaults to MainActor): a preference value is not
/// main-actor state, and `AppearanceStore` reads `stored(_:)` from its own init.
nonisolated enum AppearanceChoice: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    /// The neighbour-facing word. Plain, not clever — an appearance switch is not
    /// the place for voice.
    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    /// What `.preferredColorScheme` is handed. `nil` IS the system case: no request,
    /// so the phone decides and keeps deciding as it changes.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    /// The UIKit spelling, for the one surface SwiftUI's preference cannot reach:
    /// `ShareCenter`'s own `UIWindow`, which is not inside the root presentation.
    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    /// Decode a persisted value. Anything unrecognised — a key from a future build,
    /// a hand-edited plist, nothing at all — is `.system`, because "follow the
    /// phone" is the only safe thing to guess on someone's behalf.
    static func stored(_ raw: String?) -> AppearanceChoice {
        guard let raw, let choice = AppearanceChoice(rawValue: raw) else { return .system }
        return choice
    }
}

/// The one owner of the appearance choice: publishes it for the root to apply and
/// mirrors it to `UserDefaults` on every change, so it survives a relaunch.
///
/// Modelled on `UtilityPrefsStore`'s local mirror — `@Published` for the live view
/// update, an injectable `UserDefaults` so a test can run over a throwaway suite and
/// build a SECOND store over the same suite to prove a relaunch reads real bytes.
/// There is no server leg: an appearance is a property of this phone, not of the
/// account, so there is nothing to sync.
@MainActor
final class AppearanceStore: ObservableObject {
    /// The app's store. Views hold this rather than an injected environment object
    /// so a DEBUG preview root or a detached window can reach the same instance.
    static let shared = AppearanceStore()

    /// The `bp.*` namespace is required — see the rename section of CLAUDE.md.
    /// Never a `hygge.*` key.
    static let defaultsKey = "bp.appearance"

    @Published var choice: AppearanceChoice {
        didSet {
            guard choice != oldValue else { return }
            defaults.set(choice.rawValue, forKey: Self.defaultsKey)
        }
    }

    private let defaults: UserDefaults

    /// `UserDefaults.standard` is nonisolated, so it is safe as a default argument
    /// even though this type is `@MainActor` — the CLAUDE.md default-argument
    /// gotcha is about main-actor-isolated defaults, which this is not.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Read before the first frame: the app must never flash the phone's
        // appearance on launch and then correct itself.
        self.choice = AppearanceChoice.stored(defaults.string(forKey: Self.defaultsKey))
    }
}

#if DEBUG
extension AppearanceStore {
    /// The town-menu control cannot be TAPPED here — this setup has no gesture
    /// automation (see CLAUDE.md) — so two flags stand in for the finger. Both go
    /// through the real `choice` setter, so they exercise the production write.
    ///
    /// * `-appearance system|light|dark` makes exactly the write a tap makes. A
    ///   FOLLOWING launch without the flag then proves the choice was persisted.
    /// * `-appearance-demo` walks the three states on a timer (pair with
    ///   `-open-menu`), so the live repaint — whole app, no relaunch — can be
    ///   recorded with the control visibly moving its selection.
    ///
    /// Compiles out of Release entirely.
    func applyDebugLaunchArguments() {
        let arguments = ProcessInfo.processInfo.arguments

        if let flag = arguments.firstIndex(of: "-appearance"),
           arguments.indices.contains(flag + 1),
           let requested = AppearanceChoice(rawValue: arguments[flag + 1]) {
            choice = requested
        }

        guard arguments.contains("-appearance-demo") else { return }
        for (step, next) in [AppearanceChoice.dark, .light, .system].enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8 + 1.6 * Double(step)) {
                self.choice = next
            }
        }
    }
}
#endif
