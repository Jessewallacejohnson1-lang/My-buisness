//
//  HyggeApp.swift
//  Hygge — a hyper-local community app for St. Joseph, MN.
//
//  Native SwiftUI build, ported from the Expo / React Native app.
//

import SwiftUI

@main
struct HyggeApp: App {
    @StateObject private var auth = AuthStore.shared

    init() {
        registerHyggeFonts()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .task { await auth.restore() }
        }
    }
}
