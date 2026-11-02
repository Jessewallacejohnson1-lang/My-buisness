//
//  BlockPartyApp.swift
//  Block Party — a hyper-local community app for St. Joseph, MN.
//
//  Native SwiftUI build, ported from the Expo / React Native app.
//

import SwiftUI
import MapboxMaps

@main
struct BlockPartyApp: App {
    @StateObject private var auth = AuthStore.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        registerBlockPartyFonts()
        MapboxOptions.accessToken = MAPBOX_ACCESS_TOKEN
    }

    var body: some Scene {
        WindowGroup {
            // The launch plays over the app on every fresh start (Jesse, 2026-11-01, reversing
            // 2026-09-18's no splash): the Town's ball bounces off Bp and becomes its !. The app
            // loads underneath from the first frame and never waits on it (`LaunchBall`).
            LaunchHost {
                RootView()
                    .environmentObject(auth)
                    .task {
                        await auth.restore()
                        // The quiet anonymous account, made only once restore has found
                        // there is no stored session.
                        await auth.ensureAccount()
                    }
                    .task { await PlaceSeeder.seedIfRequested() }   // DEBUG: -seed-places one-time POI seed
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Offline at first launch: try again when the app comes back.
            if phase == .active { Task { await auth.ensureAccount() } }
        }
    }
}
