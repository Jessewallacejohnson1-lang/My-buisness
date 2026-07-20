# Share Reveal Animation — Design Spec

**Date:** 2026-07-11
**Status:** Approved (design), pending implementation plan
**Author:** Jesse + Claude

## Summary

Port Duolingo's "Share this sentence" reveal into Block Party as a **reusable, app-wide
share experience**. On any share action, instead of jumping straight to the iOS
share sheet, the app first springs up a **preview card of exactly what is being
shared** over a dimmed backdrop, alongside a Duolingo-style row of share targets
(Messages · Save image · More). The actual send happens from that sheet.

The goal is a ~99% copy of the reference motion, and a single primitive that every
current and future share point in the app routes through.

### Reference

Source: user screen recording of Duolingo's share flow (`Screen Recording
2026-07-11 at 2.44.06 PM.mov`, 6.82s, ~3 loops). Frames were extracted and
studied (montage in the working scratchpad). The decoded motion is captured in
the Motion section below. The reference end-state: a centered white content card
(what you're sharing) over a dark scrim, with a bottom sheet titled
"SHARE THIS SENTENCE" and three round targets: Messages (green), Save image, More.

## Goals

- Reproduce the reveal motion ~99%: spring scale-up of a preview card + backdrop
  dim + concurrent bottom sheet.
- Show the user **exactly what they're sharing** before they send (the preview
  card is the same view that gets rendered to the shared image).
- One reusable primitive used **everywhere** a share happens today, and trivially
  adopted by anything built in the future (one call site line).
- Copy the Duolingo target row exactly: Messages · Save image · More.
- Stay on-brand: Block Party design tokens for chrome, no drawn mascots/illustrations
  (preview cards use the existing typographic `InviteCard` language).

## Non-goals

- No new backend, tables, or network calls. This is a client-only UI layer over
  the existing share content.
- No redesign of `InviteCard`'s visual content (only how/when it's presented).
- No social/share analytics in v1.

## Motion spec (the 99% copy)

Constants below are the starting point; final values are tuned in-sim against the
reference frame montage (per the app's animation-verification discipline).

| Element      | From → To                       | Curve                                   | Timing |
|--------------|----------------------------------|-----------------------------------------|--------|
| Scrim        | opacity 0 → ~0.55 (black)        | `easeOut`                               | ~0.28s |
| Preview card | scale 0.32 → 1.0 + opacity 0 → 1 | `.spring(response: 0.42, damping: 0.74)` (soft overshoot + settle), anchor `.center` | ~0.45s |
| Bottom sheet | offset (below → rest) + fade     | `.spring(response: 0.45, damping: 0.85)`, concurrent | ~0.45s |
| Dismiss      | reverse of all three             | `.spring(response: 0.32, damping: 0.9)` (quicker, no overshoot) | ~0.3s |

- Light haptic on present, and on each target tap.
- **Reduce Motion** (`@Environment(\.accessibilityReduceMotion)`): replace the
  scale spring with a plain cross-fade; scrim + sheet still fade.
- The three elements move together — that concurrency is what reads as "smooth."

## Architecture

### `ShareCenter` (`@MainActor final class ... ObservableObject`, singleton `.shared`)
The single entry point. Public API:

```swift
ShareCenter.shared.present(_ payload: SharePayload)
```

Owns the current payload + reveal phase (`hidden`/`presenting`/`shown`/
`dismissing`), and manages the overlay window's lifecycle. Guards against
double-present. Dismisses on app background.

### Overlay `UIWindow`
The reveal renders in a lightweight passthrough `UIWindow` placed **above
everything** — the tab bar and any active `.sheet` (Profile's share is triggered
from inside a sheet, so a SwiftUI root `.overlay` cannot cover it). This is what
lets the dim cover the full screen exactly like the reference.

- A single `UIHostingController` hosting `ShareRevealView`, with a clear
  background so the app shows through the scrim.
- The window is created on first present and torn down (or hidden) on dismiss.
- Window level above normal, below system alerts. Passthrough when hidden.

### `SharePayload` (value type)
Describes one share:

- `preview: AnyView` — the card, shown in the reveal **and** rendered to the
  shared image (single source of truth → "what you see is what you send").
- `title: String` — sheet header, e.g. `"SHARE THIS EVENT"`.
- `shareText: String` — accompanying text / link.
- `includesImage: Bool` — whether the share carries a rendered image; drives
  whether the "Save image" target appears.
- Convenience factories for the two v1 content kinds (event invite, app invite).

### `ShareRevealView` (SwiftUI)
- Full-bleed black scrim (tap-to-dismiss).
- Centered preview card (`payload.preview`) with the scale/opacity spring.
- Bottom sheet: rounded top corners, `Hue.paper` surface, `BlockPartyMetrics`
  shadow, a close **X** (top-left), a `.mono(12).tracking(2)` title, and the
  target row.

### `ShareTargets` (targets + platform helpers)
- **Messages** — green (iMessage) circle → `MFMessageComposeViewController`
  seeded with image + text. If `MFMessageComposeViewController.canSendText()` is
  false (e.g. simulator), the target is hidden or routed to "More".
- **Save image** — neutral circle, down-arrow → render `payload.preview` via
  `ImageRenderer` (scale 3) → save to Photos. Requires
  `NSPhotoLibraryAddUsageDescription`. On denial, a gentle inline message; never
  crash.
- **More** — neutral circle, "…" → the existing `ActivityView`
  (`UIActivityViewController`) with image + text.

Rendering reuses the existing `ImageRenderer` pattern already in
`InviteCard.swift`.

## Integration / rollout ("everywhere")

Each current share point calls `ShareCenter.shared.present(...)` with its own
preview card:

| Call site | File | Preview card | Title |
|-----------|------|--------------|-------|
| `EventInviteCircle` | `Features/Activities/ActivitiesView.swift` | `InviteCard(event…)` | SHARE THIS EVENT |
| `InviteButton` | `Features/Components/InviteCard.swift` | `InviteCard(…)` | SHARE THIS EVENT |
| Profile "Invite a neighbor" | `Features/Profile/ProfileView.swift` | branded "Join me on Block Party" card | SHARE BLOCKPARTY |
| Profile hero `ShareLink` | `Features/Profile/ProfileComponents.swift` | same app-invite card | SHARE BLOCKPARTY |

The two Profile `ShareLink`s become `Button`s that call `ShareCenter`. A small
app-invite preview card (typographic, tokenized — no illustration) is added for
the "SHARE BLOCKPARTY" case so it also carries an image (Save image applies).

**Future shares:** one line — `ShareCenter.shared.present(SharePayload(...))`.
Documented in the `ShareCenter.swift` header and in `CLAUDE.md`.

## Files

**New** (`BlockParty/Features/Share/`):
- `ShareCenter.swift` — coordinator + overlay-window management + `SharePayload`.
- `ShareRevealView.swift` — the reveal UI (scrim, card, sheet).
- `ShareTargets.swift` — target buttons + Messages/Photos/ActivityView helpers.

**Changed:**
- `Features/Components/InviteCard.swift` — `InviteButton` routes to `ShareCenter`.
- `Features/Activities/ActivitiesView.swift` — `EventInviteCircle` routes to `ShareCenter`.
- `Features/Profile/ProfileView.swift` — invite `ShareLink` → `ShareCenter`.
- `Features/Profile/ProfileComponents.swift` — hero `ShareLink` → `ShareCenter`.
- `App/RootView.swift` — install/attach the overlay window host (or `ShareCenter` self-manages; call site TBD in plan).
- `Info.plist` — add `NSPhotoLibraryAddUsageDescription`.
- `CLAUDE.md` — document the share primitive.

## Error handling & edge cases

- **Messages unavailable** (simulator / no iMessage): hide the Messages target or
  route it to the iOS share sheet; never present a dead composer.
- **Photos add denied**: inline, non-blocking message; no crash, no repeated
  prompts.
- **Reduce Motion**: cross-fade instead of scale spring.
- **Double present**: ignore a second `present` while one is active (or replace).
- **Backgrounding** mid-reveal: dismiss cleanly, tear down the window.
- **Overlay above sheets**: verified specifically from the Profile sheet path.
- **Dismiss affordances**: tap scrim, tap X, and (optional) swipe-down on sheet.

## Verification

No XCTest target. "Verified" = **builds clean (0 warnings)** + **confirmed in the
simulator**:

- Add a `-share-demo` DEBUG launch argument that immediately presents a sample
  reveal, so the animation can be screenshotted/recorded headlessly.
- Record the sim reveal, extract frames, build a montage, and compare
  side-by-side with the reference Duolingo montage; tune spring constants until
  the motion matches ~99%.
- Screenshot each rewired call site (event share, app invite) to confirm the
  correct preview card renders.
- Confirm the dim covers the tab bar (Explore path) and the Profile sheet
  (Profile path).

## Open questions / to resolve in the plan

- Exact overlay-window install point (`RootView` vs. `ShareCenter` self-managed
  via `UIApplication.shared.connectedScenes`).
- Whether the sheet supports interactive swipe-to-dismiss in v1 (reference has a
  close X; swipe is a nice-to-have).
- Final app-invite preview card copy/layout ("Join me on Block Party in St. Joseph…").
