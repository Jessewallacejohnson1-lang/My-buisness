# Share Reveal Animation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a reusable, app-wide "share reveal" — on any share, a preview card of exactly what's being shared springs up over a dimmed backdrop with a Duolingo-style target row (Messages · Save image · More), copied ~99% from the reference recording.

**Architecture:** A `@MainActor` singleton `ShareCenter.shared` presents a SwiftUI `ShareRevealView` inside a dedicated overlay `UIWindow` above everything (tab bar + any `.sheet`). The preview card is a single `AnyView` used both for on-screen display and for `ImageRenderer` output, so what you see is what you send. All existing share call sites route through `ShareCenter.shared.present(_:)`.

**Tech Stack:** SwiftUI + UIKit interop (`UIWindow`, `UIHostingController`, `MFMessageComposeViewController`, `PHPhotoLibrary`, `UIActivityViewController`, `ImageRenderer`). No new SPM dependencies.

## Global Constraints

- **iOS deployment target 26.5, Swift 5.** SwiftUI-first; UIKit interop is fine (the app already uses it).
- **No new SPM dependencies** — only `mapbox-maps-ios` is allowed.
- **"Verified" = builds clean (0 warnings) + confirmed in the simulator via screenshots.** There is NO XCTest target. Each task's verification is a build (prefer XcodeBuildMCP `build_sim`; raw fallback below) plus, for UI, a sim screenshot. TDD's "write failing test" maps to "add the demo trigger / build and observe."
- **DerivedData trap:** resolve `BUILT_PRODUCTS_DIR` via `xcodebuild -showBuildSettings`; `simctl install` OVER the app — never `uninstall` (it wipes `hygge.onboarded` and bounces to onboarding).
- **Design tokens only.** Use `Hue.*`, `Radius.*`, `HyggeMetrics.*`, the `.mono/.sans/.display/.sansSemibold/.monoMedium` font helpers, `PressableStyle`, `Haptics`. No raw hex or ad-hoc spacing that a token covers (the only allowed raw color here is the black scrim, matching the existing place-expansion overlay `Color.black.opacity(0.45)`).
- **No drawn mascots/illustrations.** Preview cards are typographic/tokenized only (reuse `InviteCard`'s language). Real photos or vector UI only.
- **Neighborly voice, real data only.** No inflated counts, no badges/streaks.
- **Motion:** spring, concurrent choreography. Honor `@Environment(\.accessibilityReduceMotion)` (cross-fade instead of scale). Fire `Haptics.light()` on present + each target tap.
- **Commits:** frequent; end every commit message with `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.

### Build / screenshot reference (raw fallback)

```bash
# Build (Debug, iPhone 17 sim). Prefer XcodeBuildMCP build_sim.
xcodebuild -project Hygge.xcodeproj -scheme Hygge -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -20

# Resolve the REAL build output, install over, launch with a debug flag, screenshot
UDID=$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)
DIR=$(xcodebuild -project Hygge.xcodeproj -scheme Hygge -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' -showBuildSettings \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR =/{print $2; exit}')
xcrun simctl install "$UDID" "$DIR/Hygge.app"
xcrun simctl launch "$UDID" Jesse.Hygge -share-demo
xcrun simctl io "$UDID" screenshot /tmp/share.png
```

---

## File Structure

**New — `Hygge/Features/Share/`:**
- `ShareCenter.swift` — `SharePayload` (value type) + `ShareCenter` (`@MainActor final class ObservableObject`, singleton) + overlay `UIWindow` lifecycle + imperative presentation of Messages/ActivityView. One responsibility: *own the share state and the window*.
- `ShareRevealView.swift` — the SwiftUI reveal: scrim + centered preview card + bottom sheet chrome + the motion. One responsibility: *the visual + animation*.
- `ShareTargets.swift` — the target row + platform helpers: `MessagesComposer` (MFMessageComposeViewController), `PhotoSaver` (PHPhotoLibrary add), and the "More" ActivityView bridge. One responsibility: *the send actions*.
- `AppInviteCard.swift` — the typographic "SHARE HYGGE" preview card (no illustration). One responsibility: *the app-invite card visual*.

**Modified:**
- `Hygge.xcodeproj/project.pbxproj` — add `INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription` to both build configs.
- `Hygge/Features/Components/InviteCard.swift` — `InviteButton` routes to `ShareCenter`; keep `InviteCard` + `ActivityView` (reused).
- `Hygge/Features/Activities/ActivitiesView.swift` — `EventInviteCircle` routes to `ShareCenter`.
- `Hygge/Features/Profile/ProfileView.swift` — the app-invite `ShareLink` (line 210) becomes a `Button` → `ShareCenter`.
- `Hygge/App/RootView.swift` — DEBUG `-share-demo` launch arg triggers a sample reveal on appear.
- `CLAUDE.md` — document the share primitive.

---

## Task 1: `SharePayload` + `ShareCenter` skeleton + overlay window (bare scrim)

**Files:**
- Create: `Hygge/Features/Share/ShareCenter.swift`
- Modify: `Hygge/App/RootView.swift` (add `-share-demo` demo trigger)

**Interfaces:**
- Produces:
  - `struct SharePayload { let preview: AnyView; let title: String; let shareText: String; let includesImage: Bool }`
    - `init<V: View>(title: String, shareText: String, includesImage: Bool, @ViewBuilder preview: () -> V)`
    - `static func event(title:dateLabel:time:location:) -> SharePayload`
    - `static func appInvite() -> SharePayload`
  - `final class ShareCenter: ObservableObject` (`@MainActor`), singleton `static let shared`
    - `@Published private(set) var payload: SharePayload?`
    - `@Published var revealed: Bool` (drives the spring; false = off-state)
    - `func present(_ payload: SharePayload)`
    - `func dismiss()`

- [ ] **Step 1: Create `ShareCenter.swift` with `SharePayload` + the coordinator + a bare passthrough window that shows a dim scrim.**

```swift
//
//  ShareCenter.swift
//  Hygge — the one entry point for the app-wide "share reveal".
//
//  Any share in the app calls `ShareCenter.shared.present(...)`. The reveal is a
//  preview card of exactly what's being shared (the same view is rendered to the
//  shared image), springing up over a dimmed backdrop with a Duolingo-style
//  target row. Ported from a reference recording — see
//  docs/superpowers/specs/2026-07-11-share-reveal-animation-design.md.
//
//  To add a NEW share anywhere in the app, that's the whole integration:
//      ShareCenter.shared.present(SharePayload(title: "SHARE THIS THING",
//                                              shareText: "…",
//                                              includesImage: true) { MyCard(…) })
//

import SwiftUI
import UIKit

/// Describes one share: the card to preview + render, the sheet title, the text,
/// and whether a rendered image is part of the share (drives "Save image").
struct SharePayload: Identifiable {
    let id = UUID()
    let preview: AnyView
    let title: String
    let shareText: String
    let includesImage: Bool

    init<V: View>(title: String,
                  shareText: String,
                  includesImage: Bool,
                  @ViewBuilder preview: () -> V) {
        self.title = title
        self.shareText = shareText
        self.includesImage = includesImage
        self.preview = AnyView(preview())
    }
}

@MainActor
final class ShareCenter: ObservableObject {
    static let shared = ShareCenter()
    private init() {}

    @Published private(set) var payload: SharePayload?
    /// The off→on state the reveal animates against. false = card small/hidden.
    @Published var revealed: Bool = false

    private var window: UIWindow?

    func present(_ payload: SharePayload) {
        guard self.payload == nil else { return }   // one at a time
        self.payload = payload
        self.revealed = false
        showWindow()
        Haptics.light()
        // Let the reveal render in its off-state, then spring it in next runloop.
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.74)) {
                self.revealed = true
            }
        }
    }

    func dismiss() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
            self.revealed = false
        }
        // Tear down after the dismiss spring settles.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) { [weak self] in
            guard let self, self.revealed == false else { return }
            self.window?.isHidden = true
            self.window = nil
            self.payload = nil
        }
    }

    private func showWindow() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }

        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1          // above the tab bar and any .sheet
        window.backgroundColor = .clear
        let host = UIHostingController(rootView: ShareRevealView())
        host.view.backgroundColor = .clear
        window.rootViewController = host
        window.isHidden = false
        self.window = window
    }

    /// The topmost VC in the overlay window — the presenter for Messages / the
    /// iOS share sheet (used by ShareTargets in a later task).
    var overlayPresenter: UIViewController? { window?.rootViewController }
}
```

- [ ] **Step 2: Add a temporary bare `ShareRevealView` so the window has content that compiles (scrim only; the real card/sheet come in Tasks 2–3).**

Create the file `Hygge/Features/Share/ShareRevealView.swift` with a scrim-only first version:

```swift
//
//  ShareRevealView.swift
//  Hygge — the share reveal UI (scrim + preview card + target sheet).
//

import SwiftUI

struct ShareRevealView: View {
    @ObservedObject private var center = ShareCenter.shared

    var body: some View {
        ZStack {
            Color.black
                .opacity(center.revealed ? 0.55 : 0)
                .ignoresSafeArea()
                .onTapGesture { center.dismiss() }
        }
        .animation(.easeOut(duration: 0.28), value: center.revealed)
    }
}
```

- [ ] **Step 3: Wire a DEBUG `-share-demo` trigger in `RootView`.**

In `Hygge/App/RootView.swift`, add a demo presenter. Add this modifier to the `MainTabsView(...)` call inside `RootView.body` (around line 89), or to `MainTabsView`'s root `ZStack`. Add to `MainTabsView.body`'s outer `ZStack` (after `.sheet(isPresented: $composing)`):

```swift
        #if DEBUG
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-share-demo") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    ShareCenter.shared.present(
                        SharePayload(title: "SHARE THIS EVENT",
                                     shareText: "Come to Farmers Market with me — Sat 9am. (via Hygge)",
                                     includesImage: true) {
                            InviteCard(title: "Farmers Market",
                                       dateLabel: "Saturday, Jul 12",
                                       time: "9:00 AM",
                                       location: "College Ave")
                        })
                }
            }
        }
        #endif
```

- [ ] **Step 4: Build clean + screenshot the bare scrim over the tab bar.**

Build (XcodeBuildMCP `build_sim` or the raw command in Global Constraints). Expected: **0 warnings, build succeeds.** Then install-over, `launch … -share-demo`, screenshot.
Expected: after ~0.6s the screen dims (~55% black) covering the whole screen **including the tab bar**; tapping anywhere clears it.

- [ ] **Step 5: Commit.**

```bash
git add Hygge/Features/Share/ShareCenter.swift Hygge/Features/Share/ShareRevealView.swift Hygge/App/RootView.swift
git commit -m "$(printf 'feat(share): ShareCenter + overlay window scaffold\n\nApp-wide share coordinator presenting a full-screen dim scrim in a\ndedicated UIWindow above the tab bar and sheets. -share-demo debug\ntrigger for headless verification.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

## Task 2: Preview card — centered, spring scale-up

**Files:**
- Modify: `Hygge/Features/Share/ShareRevealView.swift`

**Interfaces:**
- Consumes: `ShareCenter.shared.payload` (`SharePayload?`), `ShareCenter.shared.revealed` (`Bool`).
- Produces: the reveal now renders `payload.preview` centered with the scale/opacity spring.

- [ ] **Step 1: Render the preview card with the scale + opacity spring.**

Replace the body of `ShareRevealView` with:

```swift
struct ShareRevealView: View {
    @ObservedObject private var center = ShareCenter.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var cardScale: CGFloat {
        if reduceMotion { return center.revealed ? 1 : 1 }   // no scale under Reduce Motion
        return center.revealed ? 1.0 : 0.32
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(center.revealed ? 0.55 : 0)
                .ignoresSafeArea()
                .onTapGesture { center.dismiss() }
                .animation(.easeOut(duration: 0.28), value: center.revealed)

            if let payload = center.payload {
                VStack {
                    Spacer(minLength: 0)
                    payload.preview
                        .scaleEffect(cardScale, anchor: .center)
                        .opacity(center.revealed ? 1 : 0)
                        .frame(maxWidth: 360)
                        .padding(.horizontal, 24)
                    Spacer(minLength: 0)
                }
                .allowsHitTesting(false)   // taps fall through to the scrim (dismiss)
            }
        }
    }
}
```

Note: the card scale spring is driven by `ShareCenter.present`'s `withAnimation(.spring(response: 0.42, dampingFraction: 0.74))`. Under Reduce Motion, `cardScale` stays 1 and only opacity cross-fades.

- [ ] **Step 2: Build clean + screenshot the reveal.**

Build (0 warnings). Install-over, `launch … -share-demo`, screenshot after ~1.2s.
Expected: the `InviteCard` ("YOU'RE INVITED / Farmers Market …") sits centered over the dim, at full size.

- [ ] **Step 3: Record the reveal and montage it (motion check).**

Record the sim during the reveal and extract frames into a montage (same method used to decode the reference):

```bash
UDID=$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)
xcrun simctl launch "$UDID" Jesse.Hygge -share-demo
xcrun simctl io "$UDID" recordVideo --codec=h264 /tmp/reveal.mp4 &
REC=$!; sleep 2; kill -INT $REC; wait $REC 2>/dev/null
# extract frames with the AVFoundation swift extractor from the scratchpad, then montage
```

Expected: card scales from small→full with a soft settle over ~0.45s; scrim fades in concurrently. Exact constants tuned in Task 6.

- [ ] **Step 4: Commit.**

```bash
git add Hygge/Features/Share/ShareRevealView.swift
git commit -m "$(printf 'feat(share): spring-reveal the preview card\n\nCentered preview card scales 0.32->1.0 with a soft settle over the dim;\nReduce Motion cross-fades instead. Card is the payloads own view.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

## Task 3: Bottom sheet chrome — close X, title, target row container

**Files:**
- Modify: `Hygge/Features/Share/ShareRevealView.swift`

**Interfaces:**
- Consumes: `payload.title`, `payload.includesImage`, `ShareCenter.shared.revealed`.
- Produces: a `bottomSheet` subview with a close button, a `.mono(12).tracking(2)` title, and a horizontal row placeholder that Task 4 fills with real targets.

- [ ] **Step 1: Add the bottom sheet, pinned to the bottom, sliding up + fading concurrently.**

Add to `ShareRevealView` (inside the top-level `ZStack`, aligned to bottom). Change the `ZStack` to `ZStack(alignment: .bottom)` and append after the card `VStack`:

```swift
            if let payload = center.payload {
                bottomSheet(payload)
                    .offset(y: center.revealed ? 0 : 360)
                    .opacity(center.revealed ? 1 : 0)
            }
```

And add the builder + a placeholder row (real targets land in Task 4):

```swift
    @ViewBuilder
    private func bottomSheet(_ payload: SharePayload) -> some View {
        VStack(spacing: 18) {
            HStack {
                Button { center.dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Hue.ink3)
                }
                .buttonStyle(PressableStyle(scale: 0.9))
                Spacer()
                Text(payload.title)
                    .font(.mono(12)).tracking(2)
                    .foregroundStyle(Hue.ink3)
                Spacer()
                Color.clear.frame(width: 16, height: 16)   // balances the X
            }

            HStack(spacing: 28) {
                // Task 4 replaces this placeholder with real targets.
                Color.clear.frame(height: 76)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 34)
        .frame(maxWidth: .infinity)
        .background(Hue.paper)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: Radius.xl,
                                          topTrailingRadius: Radius.xl,
                                          style: .continuous))
        .ignoresSafeArea(edges: .bottom)
    }
```

- [ ] **Step 2: Build clean + screenshot.**

Build (0 warnings). `launch … -share-demo`, screenshot.
Expected: a white sheet pinned to the bottom with an "✕" left, "SHARE THIS EVENT" centered (mono, tracked), sliding up as the card springs in.

- [ ] **Step 3: Commit.**

```bash
git add Hygge/Features/Share/ShareRevealView.swift
git commit -m "$(printf 'feat(share): bottom sheet chrome (close + title)\n\nPaper sheet with rounded top, close X, mono tracked title; slides up and\nfades concurrently with the card reveal.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

## Task 4: Share targets — Messages · Save image · More (+ Photos permission)

**Files:**
- Create: `Hygge/Features/Share/ShareTargets.swift`
- Modify: `Hygge/Features/Share/ShareRevealView.swift` (drop the placeholder row in), `Hygge/Features/Share/ShareCenter.swift` (image render helper), `Hygge.xcodeproj/project.pbxproj` (Photos usage string)

**Interfaces:**
- Consumes: `ShareCenter.shared.payload`, `ShareCenter.shared.overlayPresenter` (`UIViewController?`).
- Produces:
  - `struct ShareTargetRow: View` (the three circular targets, adapts on `includesImage`).
  - `ShareCenter.renderedImage() -> UIImage?` (renders `payload.preview` at scale 3).
  - `ShareCenter.shareMore()`, `ShareCenter.sendMessages()`, `ShareCenter.saveImage()`.

- [ ] **Step 1: Add the render + send actions to `ShareCenter`.**

Append to `ShareCenter` in `ShareCenter.swift`:

```swift
    /// Render the current payload's preview card to a shareable image (scale 3).
    func renderedImage() -> UIImage? {
        guard let payload else { return nil }
        let r = ImageRenderer(content: payload.preview)
        r.scale = 3
        return r.uiImage
    }

    private func activityItems() -> [Any] {
        guard let payload else { return [] }
        var items: [Any] = [payload.shareText]
        if payload.includesImage, let img = renderedImage() { items.insert(img, at: 0) }
        return items
    }

    /// "More" → the OS share sheet, presented above the reveal.
    func shareMore() {
        guard let presenter = overlayPresenter else { return }
        Haptics.light()
        let vc = UIActivityViewController(activityItems: activityItems(), applicationActivities: nil)
        vc.popoverPresentationController?.sourceView = presenter.view
        vc.popoverPresentationController?.sourceRect = CGRect(x: presenter.view.bounds.midX,
                                                              y: presenter.view.bounds.maxY - 60,
                                                              width: 1, height: 1)
        presenter.present(vc, animated: true)
    }

    /// "Messages" → the SMS/iMessage composer seeded with image + text.
    func sendMessages() {
        guard let presenter = overlayPresenter else { return }
        Haptics.light()
        MessagesComposer.present(from: presenter,
                                 text: payload?.shareText ?? "",
                                 image: (payload?.includesImage ?? false) ? renderedImage() : nil)
    }

    /// "Save image" → write the rendered card to Photos (add-only auth).
    func saveImage() {
        guard let img = renderedImage() else { return }
        Haptics.light()
        PhotoSaver.save(img)
    }

    /// Messages target only makes sense on a device that can send texts.
    var canSendMessages: Bool { MessagesComposer.canSend }
```

- [ ] **Step 2: Create `ShareTargets.swift` — the target row + platform helpers.**

```swift
//
//  ShareTargets.swift
//  Hygge — the share sheet's target row (Messages · Save image · More) and the
//  platform bridges behind each (Messages composer, Photos save, OS share sheet).
//

import SwiftUI
import UIKit
import MessageUI
import Photos

/// The Duolingo-style row of round targets. Adapts: link-only shares (no image)
/// drop "Save image".
struct ShareTargetRow: View {
    @ObservedObject private var center = ShareCenter.shared
    let includesImage: Bool

    var body: some View {
        HStack(spacing: 30) {
            if center.canSendMessages {
                target("message.fill", "Messages", tint: .white, bg: Color(hex: 0x34C759)) {
                    center.sendMessages()
                }
            }
            if includesImage {
                target("square.and.arrow.down", "Save image", tint: Hue.ink, bg: Hue.canvas) {
                    center.saveImage()
                }
            }
            target("ellipsis", "More", tint: Hue.ink, bg: Hue.canvas) {
                center.shareMore()
            }
        }
    }

    private func target(_ symbol: String, _ label: String,
                        tint: Color, bg: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 60, height: 60)
                    .background(bg, in: Circle())
                    .overlay(Circle().stroke(Hue.hairline, lineWidth: 1))
                Text(label)
                    .font(.sans(12))
                    .foregroundStyle(Hue.ink2)
            }
        }
        .buttonStyle(PressableStyle(scale: 0.9))
    }
}

/// MFMessageComposeViewController bridge — presented imperatively from the
/// overlay window's root VC, with a retained delegate.
enum MessagesComposer {
    static var canSend: Bool { MFMessageComposeViewController.canSendText() }

    private final class Delegate: NSObject, MFMessageComposeViewControllerDelegate {
        static var retained: Delegate?
        func messageComposeViewController(_ controller: MFMessageComposeViewController,
                                          didFinishWith result: MessageComposeResult) {
            controller.dismiss(animated: true)
            MessagesComposer.Delegate.retained = nil
        }
    }

    @MainActor
    static func present(from presenter: UIViewController, text: String, image: UIImage?) {
        guard canSend else { return }
        let vc = MFMessageComposeViewController()
        vc.body = text
        if let image, let data = image.pngData() {
            vc.addAttachmentData(data, typeIdentifier: "public.png", filename: "hygge.png")
        }
        let delegate = Delegate()
        Delegate.retained = delegate
        vc.messageComposeDelegate = delegate
        presenter.present(vc, animated: true)
    }
}

/// Photos add-only save. iOS prompts for add permission on first write; the
/// usage string is NSPhotoLibraryAddUsageDescription (Task 4, Step 4).
enum PhotoSaver {
    static func save(_ image: UIImage) {
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        } completionHandler: { success, _ in
            DispatchQueue.main.async { Haptics.success() }   // gentle confirm; failures stay silent
        }
    }
}
```

Note: `Color(hex:)` is the existing initializer used throughout `HyggeColor.swift`. `0x34C759` is the system iMessage green — an intentional, recognized brand color for the Messages target (documented exception to "tokens only", like the scrim).

- [ ] **Step 3: Drop the target row into the sheet.**

In `ShareRevealView.swift`, replace the placeholder row from Task 3:

```swift
            HStack(spacing: 28) {
                Color.clear.frame(height: 76)
            }
```

with:

```swift
            ShareTargetRow(includesImage: payload.includesImage)
                .frame(minHeight: 76)
```

- [ ] **Step 4: Add the Photos usage string to both build configs.**

In `Hygge.xcodeproj/project.pbxproj`, add this line immediately after each existing `INFOPLIST_KEY_NSCalendarsWriteOnlyAccessUsageDescription = …;` line (there are two — Debug and Release):

```
				INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription = "Hygge saves the share card to your Photos when you tap Save image.";
```

- [ ] **Step 5: Build clean + screenshot the full sheet + exercise the targets.**

Build (0 warnings — `import MessageUI` / `import Photos` are system frameworks, no linking config needed). `launch … -share-demo`, screenshot.
Expected: three round targets — green **Messages**, neutral **Save image**, neutral **More** — under the title. Tapping **More** presents the iOS share sheet above the reveal. Tapping **Save image** prompts for Photos add on first use, then a success haptic.

- [ ] **Step 6: Commit.**

```bash
git add Hygge/Features/Share/ShareTargets.swift Hygge/Features/Share/ShareRevealView.swift Hygge/Features/Share/ShareCenter.swift Hygge.xcodeproj/project.pbxproj
git commit -m "$(printf 'feat(share): Messages / Save image / More targets\n\nCustom target row copied from the reference: iMessage composer, Photos\nadd-only save, and the OS share sheet. Row adapts when a share carries no\nimage. Adds NSPhotoLibraryAddUsageDescription.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

## Task 5: App-invite preview card (`AppInviteCard`)

**Files:**
- Create: `Hygge/Features/Share/AppInviteCard.swift`
- Modify: `Hygge/Features/Share/ShareCenter.swift` (add the `appInvite` + `event` factories)

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `struct AppInviteCard: View` — a typographic "Join me on Hygge" card (no illustration).
  - `SharePayload.event(title:dateLabel:time:location:) -> SharePayload`
  - `SharePayload.appInvite() -> SharePayload`

- [ ] **Step 1: Create `AppInviteCard.swift` (tokenized, no drawn art).**

```swift
//
//  AppInviteCard.swift
//  Hygge — the preview card for "SHARE HYGGE" (app invite). Typographic only,
//  matching InviteCard's language — no illustration (house rule).
//

import SwiftUI

struct AppInviteCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("ST. JOSEPH, MN")
                .font(.mono(12)).tracking(2).foregroundStyle(Hue.ink3)
            Text("Come see what's happening in town")
                .font(.display(28)).foregroundStyle(Hue.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("The town calendar, today's happenings, and a live map of what's on — in one calm place.")
                .font(.sans(15)).foregroundStyle(Hue.ink2)
                .fixedSize(horizontal: false, vertical: true)
            Rectangle().fill(Hue.hairline).frame(height: 1).padding(.top, 2)
            Text("Hygge")
                .font(.logo(20)).foregroundStyle(Hue.accent)
        }
        .padding(24)
        .frame(width: 360, alignment: .leading)
        .background(Hue.paper)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).stroke(Hue.hairline, lineWidth: 1))
        .padding(16)
        .background(Hue.canvas)
    }
}
```

Note: `Font.logo(_:)` is the app's one custom face (Atkinson Hyperlegible Bold) per `HyggeFont.swift`. If the helper signature differs, use the exact `.logo` helper as defined there.

- [ ] **Step 2: Add the payload factories to `ShareCenter.swift`.**

Append to `SharePayload` (in `ShareCenter.swift`):

```swift
extension SharePayload {
    static func event(title: String, dateLabel: String, time: String?, location: String?) -> SharePayload {
        var text = "Come to \(title) with me — \(dateLabel)"
        if let time, !time.isEmpty { text += " at \(time)" }
        if let location, !location.isEmpty { text += ", \(location)" }
        text += ". (via Hygge)"
        return SharePayload(title: "SHARE THIS EVENT", shareText: text, includesImage: true) {
            InviteCard(title: title, dateLabel: dateLabel, time: time, location: location)
        }
    }

    static func appInvite() -> SharePayload {
        SharePayload(
            title: "SHARE HYGGE",
            shareText: "Come see what's happening in St. Joseph — Hygge has the town's calendar, today's happenings, and a live map of what's on. 🌿",
            includesImage: true
        ) { AppInviteCard() }
    }
}
```

- [ ] **Step 3: Point the demo at the factory (replaces the inline payload from Task 1).**

In `RootView.swift`, replace the `-share-demo` payload body with:

```swift
                    ShareCenter.shared.present(.event(title: "Farmers Market",
                                                      dateLabel: "Saturday, Jul 12",
                                                      time: "9:00 AM",
                                                      location: "College Ave"))
```

- [ ] **Step 4: Build clean + screenshot both cards.**

Build (0 warnings). Screenshot the event demo. Then temporarily swap the demo to `.appInvite()` and screenshot the app-invite card (revert after).
Expected: event card shows the `InviteCard`; app-invite shows the tokenized "Come see what's happening in town / Hygge" card — no illustration.

- [ ] **Step 5: Commit.**

```bash
git add Hygge/Features/Share/AppInviteCard.swift Hygge/Features/Share/ShareCenter.swift Hygge/App/RootView.swift
git commit -m "$(printf 'feat(share): event + app-invite payload factories\n\nSharePayload.event reuses InviteCard; .appInvite adds a typographic\n"Share Hygge" card (no illustration, house rule).\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

## Task 6: Motion tuning + dismiss affordances (match the reference ~99%)

**Files:**
- Modify: `Hygge/Features/Share/ShareCenter.swift`, `Hygge/Features/Share/ShareRevealView.swift`

**Interfaces:**
- Consumes/Produces: no signature changes — this task tunes constants and choreography.

- [ ] **Step 1: Record the current reveal and montage it against the reference.**

Record the sim reveal (Task 2, Step 3 method), extract ~30 frames over the reveal window, montage. Open the reference montage (`/private/tmp/.../scratchpad/montage_reveal.png`) side by side.
Compare: scrim depth/fade timing, card start scale (~0.32), overshoot amount, settle time (~0.45s), and that the sheet rises concurrently.

- [ ] **Step 2: Adjust constants to match.**

Tune in `ShareCenter.present` / `dismiss` and `ShareRevealView`:
- Card spring (present): start `.spring(response: 0.42, dampingFraction: 0.74)`; if the reference has a touch more overshoot, drop damping toward `0.70`; if too bouncy, raise toward `0.78`.
- Scrim: `.easeOut(duration: 0.28)`; match to the reference's ~0.25–0.30s.
- Sheet offset spring: if it should trail the card slightly, wrap the sheet's `revealed` change in its own `.animation(.spring(response: 0.45, dampingFraction: 0.85), value: center.revealed)` on the sheet view.
- Dismiss: `.spring(response: 0.32, dampingFraction: 0.9)` — no overshoot; confirm the teardown delay in `dismiss()` (`0.36s`) outlasts it.

- [ ] **Step 3: Confirm Reduce Motion + start-scale anchor.**

Enable Reduce Motion in the sim (`xcrun simctl ui <UDID> increase_contrast`? — use Settings › Accessibility › Motion, or the launch env). Verify the card cross-fades with no scale.

- [ ] **Step 4: Re-record + re-montage; iterate Steps 2–3 until the motion matches ~99%.**

Expected: side-by-side montages are visually indistinguishable in scale trajectory, dim, and concurrency.

- [ ] **Step 5: Commit.**

```bash
git add Hygge/Features/Share/ShareCenter.swift Hygge/Features/Share/ShareRevealView.swift
git commit -m "$(printf 'feat(share): tune reveal motion to the reference (~99%)\n\nSpring constants + concurrency matched frame-by-frame against the source\nrecording montage; Reduce Motion cross-fades.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

## Task 7: Rollout — route all existing share points through `ShareCenter`

**Files:**
- Modify: `Hygge/Features/Components/InviteCard.swift`, `Hygge/Features/Activities/ActivitiesView.swift`, `Hygge/Features/Profile/ProfileView.swift`

**Interfaces:**
- Consumes: `ShareCenter.shared.present(_:)`, `SharePayload.event(...)`, `SharePayload.appInvite()`.

- [ ] **Step 1: `InviteButton` (InviteCard.swift) → ShareCenter.**

Replace `InviteButton`'s `Button` action + `@State shareItems` + `.sheet` with a direct present. New `InviteButton.body`:

```swift
    var body: some View {
        Button {
            ShareCenter.shared.present(.event(title: title, dateLabel: dateLabel, time: time, location: location))
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.and.arrow.up").font(.system(size: 12, weight: .semibold))
                Text("Invite a neighbor").font(.sansSemibold(13))
            }
            .foregroundStyle(Hue.sky700)
        }
        .buttonStyle(.plain)
    }
```

Remove the now-unused `@State private var shareItems`, `inviteText`, and `renderCard()` from `InviteButton` (the payload factory owns them now). **Keep** `InviteCard`, and **keep** `ActivityView` (ShareCenter's "More" uses `UIActivityViewController` directly, but leave `ActivityView` in place — it's small and still referenced elsewhere; verify with a grep before deleting).

- [ ] **Step 2: `EventInviteCircle` (ActivitiesView.swift) → ShareCenter.**

Replace its `Button` action + `@State shareItems` + `.sheet` + `renderCard()`:

```swift
    var body: some View {
        Button {
            ShareCenter.shared.present(.event(title: event.title,
                                              dateLabel: dateLabel,
                                              time: event.startTime,
                                              location: event.location))
        } label: {
            exploreCircleIcon("square.and.arrow.up")
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .accessibilityLabel("Invite a neighbor")
    }
```

Remove the now-unused `@State private var shareItems` and `renderCard()` (keep `dateLabel`; `inviteText` moves into the factory — delete the local copy).

- [ ] **Step 3: Profile app-invite `ShareLink` → ShareCenter.**

In `ProfileView.swift`, replace the `ShareLink(item: inviteMessage) { FeatureFace(...) }` (line ~210) with:

```swift
            Button {
                ShareCenter.shared.present(.appInvite())
            } label: {
                FeatureFace(icon: "person.badge.plus",
                            value: "Invite",
                            label: "a neighbor",
                            subtitle: "Share Hygge")
            }
            .buttonStyle(PressableStyle())
```

`inviteMessage` is now unused in `ProfileView` (the factory carries the text) — remove the `private let inviteMessage` if grep shows no other reference.

- [ ] **Step 4: Build clean + screenshot each rewired path.**

Build (0 warnings). Verify:
- Explore event share: `launch … -explore-filter events`, tap a card's share circle (or add a note that the demo covers the motion; the call-site screenshot confirms the button renders). Screenshot.
- Profile: `launch … -open-profile`, tap "Invite / a neighbor", screenshot the "SHARE HYGGE" reveal.
Expected: both present the reveal with the correct preview card; no leftover per-site `.sheet` presenting the old OS sheet directly.

- [ ] **Step 5: Commit.**

```bash
git add Hygge/Features/Components/InviteCard.swift Hygge/Features/Activities/ActivitiesView.swift Hygge/Features/Profile/ProfileView.swift
git commit -m "$(printf 'feat(share): route all share points through ShareCenter\n\nEvent invites (Explore + InviteButton) and the Profile app-invite now\npresent the reveal instead of jumping to the OS sheet. Future shares are\none present() call.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

## Task 8: Documentation

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Document the share primitive in `CLAUDE.md`.**

Under **Features**, add a short subsection:

```markdown
**Share (`Features/Share/`)** — the app-wide "share reveal" (ported ~99% from a
Duolingo reference). Any share calls `ShareCenter.shared.present(SharePayload(...))`:
a preview card of exactly what's being shared springs up over a dimmed backdrop in
a dedicated overlay `UIWindow` (above the tab bar and any sheet), with a target row
(Messages · Save image · More). The preview view is also what's rendered to the
shared image (ImageRenderer). Add a new share in one line via a `SharePayload`
factory; preview cards stay typographic (no drawn art). Verify motion with the
sim frame-montage method (spec: docs/superpowers/specs/2026-07-11-share-reveal-animation-design.md).
```

- [ ] **Step 2: Update graphify + commit.**

```bash
graphify update . 2>/dev/null || true
git add CLAUDE.md
git commit -m "$(printf 'docs(share): document the ShareCenter primitive in CLAUDE.md\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

## Self-Review (completed during authoring)

**Spec coverage:**
- Reveal motion (scrim/card/sheet springs, Reduce Motion) → Tasks 2, 3, 6 ✓
- Preview = rendered image → `SharePayload.preview` + `renderedImage()` (Tasks 1, 4) ✓
- Overlay window above tab bar + sheets → Task 1 ✓
- Target row Messages/Save image/More + adapt + fallbacks → Task 4 ✓
- Photos permission → Task 4, Step 4 ✓
- Rollout to all current share points → Task 7 (3 sites; the "4th" in the spec was `FeatureFace`, a label view, not a separate share) ✓
- App-invite card, no illustration → Task 5 ✓
- Verification via build + sim montage → every task; `-share-demo` in Task 1 ✓
- Docs → Task 8 ✓

**Placeholder scan:** No TBD/TODO in task steps. The two design-doc "open questions" are resolved: overlay window install = `ShareCenter` self-managed via `connectedScenes` (Task 1); swipe-to-dismiss = **not** in v1 (tap-scrim + X only) — YAGNI; app-invite copy = finalized in Task 5.

**Type consistency:** `present(_:)`, `dismiss()`, `revealed`, `payload`, `overlayPresenter`, `renderedImage()`, `canSendMessages`, `SharePayload.event(...)`, `.appInvite()`, `ShareTargetRow(includesImage:)` — names used identically across Tasks 1, 4, 5, 7. Reduce-Motion via `cardScale` (Task 2). ✓

## Notes for the implementer

- If `import MessageUI` / `import Photos` surface a link warning, they're system frameworks — no Xcode target config needed; a clean build confirms.
- `simctl uninstall` is forbidden (wipes onboarding) — always install OVER (see Global Constraints).
- Before deleting `ActivityView`, `inviteMessage`, or any `renderCard()`, grep the repo for other references — remove only if truly unused.
- The reference frames + montages live in the session scratchpad (`/private/tmp/.../scratchpad/frames_reveal`, `montage_reveal.png`) for the Task 6 comparison.
```
