# Ready-to-paste Claude Code prompt — Upcoming Insights, personal spotlight edition

```
ultracode

Implement the approved design in
docs/superpowers/specs/2026-07-16-upcoming-insights-personal-design.md — read it
fully first. It remakes the CONTENT of the Calendar tab's "Upcoming" Insights face
(Hygge/Features/Calendar/Insights/) into a personal town dashboard: a swipeable
spotlight-wheel hero (your event first, then the town's), a "Your Year Ahead"
interest-matched chart, a bento of my 3 onboarding-interest categories, and a
participation mini-grid. Layout, card sizes, InsightsPalette, and the shipped
tap-to-expand motion stay exactly as they are — this is a content + data swap.

Process:
1. Invoke Skill(emil-design-eng) and Skill(impeccable) before touching any UI.
   The bar is elite, restrained design: simple, clean, native-feeling motion —
   calm paged snap for the spotlight wheel, no parallax, no autoplay, Reduce
   Motion honored everywhere.
2. Branch first: feat/upcoming-personal-insights. If you use a fresh worktree,
   copy the gitignored Hygge/Config/MapboxConfig.swift into it or the build fails.
3. Orchestrate with parallel Opus-powered agents (Workflow tool, model: 'opus'):
   - Phase 1, parallel implementation agents, one per unit: (a) InsightsData pure
     logic + a swiftc -D DEBUG unit harness (spotlight ladder, dedupe, interest
     tile selection, sparse cases, pinned TZ); (b) spotlight wheel hero;
     (c) "Your Year Ahead" chart card; (d) interest bento + doorway routing into
     DayDetailView; (e) mini grid dots + CalendarModel/CommunityAPI plumbing
     (rsvpCounts goes public, two new parallel reads, signed-out degradation).
   - Phase 2: integrate on the branch, build to 0 warnings.
   - Phase 3, parallel review agents: code-reviewer; a design/animation-taste
     pass against emil-design-eng principles; a brand-honesty audit (real data
     only, honest zeros, day-part copy, no streaks/badges/imperatives).
     Fix everything CRITICAL/HIGH before proceeding.
   - Phase 4: verify per the spec — headless screenshots of every card state via
     the extended -insights-sample / new -insights-page <n> flags on a signed-out
     sim (hero pages 1–3, chart with/without interests, each bento tile expanded,
     mini grid with both dot kinds, empty-calendar state), plus a frame-montage
     for the wheel paging and bento expand motion.
4. Commit as you go (conventional commits); end with one feature-complete branch
   and a summary of screenshots taken.

Hard rules from the spec: no schema changes; interests via the existing
keyword-contains matcher over title+location; countdown framing only for the
spotlight, never recurring rhythms; social-proof line absent at zero (never
"Be the first!"); every zero renders honest; nothing about the four-slot layout
changes. Watch the repo gotchas: MainActor-default warnings (pure helpers
nonisolated), no try? on non-throwing Mapbox/style-ish calls, DerivedData path
trap when installing to the sim (resolve BUILT_PRODUCTS_DIR, install over, never
uninstall).
```
