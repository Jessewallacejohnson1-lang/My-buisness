//
//  TabPages.swift
//  Block Party — each tab stays built once visited, as UIKit's tab bar keeps its pages, so coming back
//  is instant and lands where you were (tab-lag, 2026-11-16: a rebuilt tab froze the switch about half
//  a second, measured with -tab-cycle -frame-gap-log).
//

import SwiftUI

extension EnvironmentValues {
    /// Whether this tab is the one on screen. A kept tab stays in the tree off screen, so
    /// `onAppear` and `onDisappear` no longer mark a visit: `onScreen` and `task(id: tabOnScreen)` do.
    @Entry var tabOnScreen = true
}

extension View {
    /// A tab's reads on every visit: each time it comes on screen.
    func visitTask(_ work: @escaping @MainActor () async -> Void) -> some View {
        modifier(VisitTask(work: work))
    }
}

private struct VisitTask: ViewModifier {
    let work: @MainActor () async -> Void
    @Environment(\.tabOnScreen) private var tabOnScreen

    func body(content: Content) -> some View {
        content.task(id: tabOnScreen) {
            guard tabOnScreen else { return }
            await work()
        }
    }
}

extension View {
    /// A tab's page in the shell's stack: on screen, off to the side it slides to, or (Reduce Motion)
    /// faded out; off screen it takes no touch, no VoiceOver, and leaves the tab bar's size alone.
    func tabPage(_ page: Tab, current: Tab, leaving: Tab?, reduceMotion: Bool) -> some View {
        let shown = page == current
        let shift: CGFloat = reduceMotion || shown ? 0 : page.rawValue < current.rawValue ? -1 : 1
        let visible = shown || page == leaving
        return self
            .environment(\.tabOnScreen, shown)
            // A pure slide, as before: only Reduce Motion's crossfade animates the fade.
            .opacity(visible ? 1 : 0)
            .transaction(value: visible) { if !reduceMotion { $0.animation = nil } }
            .visualEffect { content, proxy in content.offset(x: proxy.size.width * shift) }
            .allowsHitTesting(shown)
            .accessibilityHidden(!shown)
            .transformPreference(TabBarCompactKey.self) { if !shown { $0 = false } }
            .zIndex(shown ? 1 : 0)
    }

    /// Runs `appear` when this view is on screen in the tab on screen, and `disappear` when either
    /// stops: the visit `onAppear` and `onDisappear` used to mark while a tab was rebuilt each time.
    func onScreen(appear: @escaping () -> Void, disappear: @escaping () -> Void = {}) -> some View {
        modifier(OnScreen(appear: appear, disappear: disappear))
    }
}

private struct OnScreen: ViewModifier {
    let appear: () -> Void
    let disappear: () -> Void
    @Environment(\.tabOnScreen) private var tabOnScreen
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .onAppear { appeared = true }
            .onDisappear { appeared = false }
            .onChange(of: appeared && tabOnScreen, initial: true) { was, now in
                if now { appear() } else if was { disappear() }
            }
    }
}

/// A kept tab that the shell's own changes (the tab switch above all) leave alone: it is drawn again
/// only when `key` changes, or when a model its page reads changes (Observation tracks those reads
/// here). Without it every switch drew all five tabs again, since each page is made with new closures.
struct KeptTab<Content: View>: View, Equatable {
    let page: Tab
    /// The shell's own state the page is made from; the models it reads need no entry.
    let key: [AnyHashable?]
    @ViewBuilder let content: () -> Content

    static func == (a: Self, b: Self) -> Bool { a.page == b.page && a.key == b.key }

    var body: some View { content() }
}

/// The tab on screen, the tabs built so far (each stays once visited) and the one sliding off.
@MainActor @Observable
final class TabSelection {
    var tab: Tab
    var visited: Set<Tab> = []
    /// The tab sliding off during a switch, shown until its slide ends.
    var leaving: Tab?

    init(_ tab: Tab) { self.tab = tab }
}

/// Reads the selection in its own body, so only what it draws follows a switch.
struct ReadTab<Content: View>: View {
    let tabs: TabSelection
    @ViewBuilder let content: (TabSelection) -> Content

    init(_ tabs: TabSelection, @ViewBuilder content: @escaping (TabSelection) -> Content) {
        self.tabs = tabs
        self.content = content
    }

    var body: some View { content(tabs) }
}
