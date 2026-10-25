# Onboarding

The spec the onboarding flow is held to. Read it before building, rebuilding, or
changing any first-run screen.

## Status

The flow shell is built (BP app onboarding ticket 16, 2026-10-24): `Features/Onboarding/
OnboardingFlow.swift` holds the steps, the saved place (`OnboardingStore`) and the Welcome;
`OnboardingChrome.swift` the backdrop, back chevron, progress bar and Next bar. The nine
question steps are placeholders that tickets 17 to 24 fill. It is switched off
(`RootView.showsOnboarding = false`) until ticket 24 turns it on; DEBUG `-onboarding` shows it
as a first launch would. Finishing stamps `town_profiles.onboarded_at`, and a stamp already on
the server skips the flow on a reinstall.

`refs/onboarding/REFERENCE-SPEC.md` still holds the measured Duolingo press and progress
numbers the Next bar and progress bar use (section 8).

## Direction — Jesse's calls

**The spec is BP app `docs/plans/onboarding/SPEC.md`** (charted with Jesse 2026-10-23 and
2026-10-24), with its build tickets in `docs/plans/onboarding/issues/`. The Reference for every
screen is the approved mock (v7, `docs/plans/onboarding/assets/08-mock/`) and, for the Welcome,
the ticket 25 mock (`references/welcome-screen/mock.html`). It replaces the old direction here
(a near 1:1 Duolingo clone, 20 screens, 6 questions): only Duolingo's progress bar and button
press are kept. Everything below this section still holds, except where the spec says
otherwise: between steps only the question slides (Reduce Motion: a cross-fade), not a
cross-fade of the whole step.

## The bar

Onboarding is smooth and as frictionless as possible. It should feel like the app
carrying the neighbour through, not a form they have to get past. Every screen earns
its place or it does not ship: the shortest flow that still collects what the app
genuinely needs to be useful on day one.

Friction is anything that makes someone stop and think about the interface instead of
the answer — a control that moved, a step with no visible end, a question they can't
answer yet, a spinner with no shape, a keyboard where a tap would do.

## Locked rule: the primary button never moves

**The CTA sits in exactly one place and stays there for the entire flow.** Same
x-position, same y-position, same width, same height, same corner radius, on every
single step. A neighbour tapping through should be able to keep their thumb still and
advance the whole flow without re-aiming once.

A button that moves between steps forces the user to re-find it on every screen. That
re-hunt is the friction — it reads as the app being unsteady, and it is the difference
between a flow that feels premium and one that feels assembled.

What may change per step: the button's **title** (`Continue`, `Continue · 3`, `Done`)
and its **enabled state**. Nothing else. Specifically not allowed:

- A centred button on one screen and a bottom-pinned one on the next.
- A button that rides up or down with the content length (short step = button in the
  middle of the screen, long step = button at the bottom).
- A button that shifts when a secondary/skip link appears or disappears — the
  secondary slot is reserved height whether it is filled or not.
- A button that jumps when the keyboard opens. It stays anchored above the keyboard.
- A button that changes size when its title changes. The title is centred inside a
  fixed frame; width does not track the label.

The same rule applies to the rest of the chrome: back button fixed at the top-left,
progress bar fixed on the same baseline, both present on every data-collection step so
they never appear and disappear underfoot.

**How to build it so it cannot drift.** The flow shell owns the chrome and the footer;
the step views are *content only* and must never draw their own CTA. One structure,
one footer, outside the step switch:

```swift
VStack(spacing: 0) {
    OnboardingTopBar(index: step.index, total: Step.total, onBack: back)   // fixed
    stepContent                                                            // the only thing that changes
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    OnboardingFooter(title: step.ctaTitle, enabled: step.canAdvance, action: next)  // fixed
}
```

Step content that can overflow scrolls inside its own region — the footer is outside
the scroll view, so the button never rides the content. `InterestPickerView`'s `footer`
is the shape to copy (hairline, then `ContinueButton` with fixed padding, on a
`Hue.paper` bar).

Slide only the question between steps; do not move the chrome — the chrome is not part of
the transition. Reduce Motion degrades the step change to a cross-fade.

**Verify it, don't assume it.** A rebuild lands with a test that walks every step and
asserts the CTA's frame is identical throughout — a UI test reading the button's frame
per step, or a frame-montage of the flow. A build is not done until that passes.

## Frictionless rules

- **Fewest screens that still do the job.** Every step must name what the app does
  differently because of the answer. If nothing changes, cut the step.
- **Never ask for what can be derived or deferred.** Anything the app can infer, or ask
  later in context, is not an onboarding question.
- **One tap per step wherever possible.** Typing is the most expensive input; reserve
  it for the name and nothing else.
- **No dead ends.** Back always goes somewhere real, and a first step with nowhere to
  go back to shows no back button at all rather than a dead one.
- **Progress is always visible** and always honest — the bar's total is the real number
  of steps, never padded to make the flow look shorter.
- **Never block on the network.** Advance optimistically and reconcile in the
  background; a failed write surfaces later in context, it does not trap someone on
  step 3.
- **Permissions are asked in context, with the reason, at the moment they pay off** —
  never a stack of system prompts up front.
- **No value wall.** The app shows something worth seeing before it asks for anything.
- **Resume where they left off.** Quitting mid-flow and relaunching returns to the same
  step with the same answers, never back to screen one.
- **Loading is a skeleton, never a spinner** (see CLAUDE.md / DESIGN.md). An onboarding
  step waiting on a fetch shows the shape of what is coming.
- **Dynamic Type and Reduce Motion are requirements, not polish.** The reference flow
  was audited as *not* supporting Dynamic Type; a rebuild does not inherit that. Text
  takes a role via `BlockPartyFont`, never a raw size, and every reveal degrades to a
  cross-fade.

## Bans

- No button that moves between steps, for any reason.
- No progress bar that jumps backwards or changes its total mid-flow.
- No screen whose only purpose is to announce a feature.
- No fabricated counts, seeded neighbours, or fake activity used to make the town look
  populated during onboarding.
- No system permission prompt before the user has seen why it matters.
- No step that cannot be completed without a network round-trip.
