# "Steal This": A Prioritized Playbook for Block Party

Read this before design or launch-strategy work. The `block-party-brand` skill
governs *how* things look; this file governs *what to build and in what order*,
and *why* — the competitive precedents behind the decisions.

---

## TL;DR

- **Adopt the Partiful model as the north star** — a pure black-and-white action system where color appears only in photography and semantic status states, paired with SMS-first (not push-first) engagement. Per CNBC (Apr 2025), citing Sensor Tower, Partiful averaged ~500K MAU in Q1 2025 (+400% YoY) and reports 60%+ of active users check in weekly. That recipe maps almost perfectly onto Block Party's monochrome brand and four tabs.
- **Win one town completely before touching the next** — copy Facebook's college-by-college and Front Porch Forum's town-by-town discipline: seed content before users arrive, set a hard critical-mass threshold per town (Nextdoor requires 10 verified households; Front Porch Forum goes live at 100 residents), and only expand when Saint Joseph is dense and active.
- **Treat the rebrand as an icon/name migration, not a fresh app** — keep the same bundle identifier and App Store listing to preserve ratings and history, phase the visual change, and communicate it in release notes and in-app. Instagram's 2016 gradient and Airbnb's Bélo both survived brutal launch backlash because they kept the core shape recognizable and doubled down; Twitter→X did the opposite and cratered (per Sensor Tower via TechCrunch, ~78% of US iOS reviews of X were 1-star in the weeks after the rename, vs ~50% before).

---

## Key Findings

- **The strongest single template for Block Party is Partiful** — it proves a monochrome, photography-forward UI plus text-message mechanics wins an event-planning audience. Its entire action hierarchy runs on black and white; color is reserved exclusively for RSVP states (green/amber/red = Going/Maybe/Can't) and full-bleed photography.
- **Pure-mono brands need a rule for where the one non-neutral color is allowed.** The best minimal apps don't go colorless — they ration color to a single job: Partiful (status only), Linear (one accent for the single primary action per view), Notion (purple CTA only). Block Party's rule: photography carries color, plus a 3-state status palette. Nothing else.
- **Hyperlocal engagement is driven by trust primitives and small-town density, and killed by negativity and staleness.** Front Porch Forum (~250K members, roughly half of Vermont's adults, with human moderators) surveys at 80% "people treat each other with respect" and 78% "reliable source of information" (UT-Austin Center for Media Engagement, 2023). Nextdoor's weak volunteer moderation produced negativity and user exodus. Meetup rotted from organizer fee-extraction and product stagnation.
- **Rebrands survive when the core mark stays recognizable and the change is phased and explained**; they fail when rushed, over-explained, or continuity-breaking. Instagram and Airbnb survived mockery; Twitter→X torched its ratings.
- **Small-market rollouts work on seeding + density thresholds a solo founder can actually hit.** Facebook got >50% of Harvard undergrads in its first month before expanding; Front Porch Forum grew town-by-town as demand allowed.

---

## 1. Brand system & visual language — what to steal

### Partiful (primary model) → brand system, all tabs

- **Pure black/white action hierarchy:** primary CTA = solid black fill, white text. No colored button fills anywhere.
- **Color only as semantic status:** green `#31C431`, amber `#FFAE00`, red — exclusively for RSVP states, never decorative. Block Party maps these to Going / Interested / Can't on Activities and Calendar, plus open/closed or happening-now on Map.
- **Photography as the only color layer:** white canvas, full-bleed photographic art carries all the color. In Block Party: event photos, trail/park imagery, venue photos.
- **Custom display face + workhorse UI face:** distinctive rounded-geometric display type reserved for big headlines; neutral sans for all UI text. Block Party's geometric face (Jost/Futura-style) follows the same split — display for the wordmark, Today's brief headline, and section titles; legible sans for body.

### Linear → radii, borders, restraint

- A **three-radius vocabulary** (e.g., cards 12 / buttons 6 / pills full) — pick three radii, never deviate. Block Party's block motif argues for tighter radii.
- **Hairline borders (0.5–1px) instead of drop shadows** for surface separation; elevation via borders and a surface ladder.
- One accent used only for the **single primary action per view**, never decoration.
- Type capped at **medium weight** with tight negative tracking at display sizes — restraint over heavy bold.

### Notion → buttons are rectangles, warmth

- Rectangular ~8px-radius buttons (not pills) on a warm-minimal canvas — supports Block Party's blocks-not-pills direction. Proves a single accent can own the CTA role in an otherwise neutral, content-first UI.

### Airbnb → the color lesson

- Airbnb's coral Rausch (`#FF5A5F`) is the family Hygge is leaving. Airbnb restricts it to the most important elements and lets **photography extend the color strategy**. Lesson: dropping coral means photography must do the emotional warming coral did — invest in photo quality and coverage.
- Cereal is a geometric sans reserved for brand use over a legible body face — same display/body split as above.

### Muji / Uniqlo → "no-brand" positioning as a small-town asset

- Plain typography, deliberate white space, product/photography doing the work, near-zero ornamentation. Minimalism reads as **calm and trustworthy** — right for a civic tool, and the opposite of Nextdoor's alarm-driven feed. Muji grows on word of mouth and quiet consistency across every touchpoint — a realistic solo-founder model.

### Empty states → every tab (where minimal apps live or die)

In a new town most screens start empty, so **empty states ARE the product and onboarding.**

- Treat every first-use empty state as onboarding, not an error: name the **value** (not the feature), show the **shape of success** (a ghost/preview row), give **one verb-first CTA**.
- Two parts instruction, one part delight. No apologies ("oops, nothing here yet").
- Preload starter content so no screen is ever fully blank at launch (see seeding, below).

---

## 2. Hyperlocal & community patterns — what works, what to avoid

### Front Porch Forum (Vermont) → the closest precedent

- **Real names + verified street address at signup** — the biggest driver of civility and trust.
- **Human moderation** kept in the loop even as they automate.
- **A per-town go-live threshold:** forums start in registration mode and switch on at 100 residents. Adopt an explicit town-activation threshold.
- **Deliberately minimal feed** — no reactions, no comment pile-ons, digest-style delivery — structurally suppresses pile-on negativity.
- **Utility moments drive adoption** (storms, COVID). Today's brief + weather is the everyday-utility hook; lean into closures, weather, and emergencies as retention anchors.

### Nextdoor → seeding mechanics to copy, failure modes to avoid

- **Copy the seeding threshold:** a pilot neighborhood needs 10 verified members in 21 days or it expires. Block Party equivalent: don't open a town until N verified residents + seeded content exist.
- **Copy the profile-completion nudge:** Nextdoor reported a profile photo drove 180% more profile views and 46% more connection requests.
- **Avoid the negativity trap:** keep categories oriented to *doing things* (events, clubs, trails, parks), not crime/complaints; no raw social feed in v1; if discussion ever ships, use FPF-style human moderation + real identity.

### Partiful → engagement mechanics (SMS-first, not push-first)

- **SMS as primary channel**, cross-platform by design; texts don't rot in spam folders and don't require daily app opens.
- **Reminder cadence to copy exactly:** auto-reminder ~2 hours before an event to "Going" RSVPs, ~1 week out to "Maybe"/un-RSVP'd.
- **Text blast to a segment** (event attendees, or a whole town) before and after events — lightweight host tooling worth cloning.
- **Show who's coming:** guest-list transparency builds hype and actual attendance. Surface attendee counts and opt-in faces on event pages.
- **Anti-feed positioning is itself the brand:** a calendar/utility that gets people to log off is a trust asset — aligns with FPF/Muji calm over Nextdoor anxiety.

### Snapchat Map / Life360 → Map tab

- Snap Map's Places: tap a pin → venue listing → today's happenings there. That's the core Map interaction to nail.
- **Privacy-by-default is table stakes** if people (vs venues) ever appear on the map: ghost mode default, mutual opt-in only. Keep the Map venue-first.

### Meetup → what staleness looks like (avoid)

- Died by rising organizer fees (pushing hosts to Luma/Facebook) and a decade of product stagnation — a stale event search engine full of promotional spam.
- Lessons: keep host/organizer costs **free in early towns**; keep events fresh with recurring/duplicable events and real curation; don't let Activities fill with promo listings.

---

## 3. Rebrand execution — Hygge → Block Party

### Preserve continuity (technical spine)

- **Superseded 2026-08-09:** the original recommendation was to keep the bundle identifier and App Store record, because a new bundle ID creates a new app and forfeits listing/TestFlight continuity. Jesse accepted that cost after confirming the app is pre-launch and chose a full identifier purge. The bundle id is now `Jesse.BlockParty`; the required new App Store Connect record and Google Places restriction update remain outstanding. `DECISIONS.md` is authoritative.
- Name changes are allowed but reviewed; expect a temporary **ASO wobble** while the algorithm re-associates. Do keyword work so "Block Party" + descriptive subtitle terms are earned back deliberately.
- **Phase the rollout** so users can re-associate icon and name; no hard overnight swap.

### Communicate the change (trust spine)

- Explain the rename in release notes, an in-app message, and owned channels. Consider a **"formerly Hygge" subtitle for ~30 days**.
- Respond to reviews during the transition; route complaints to a support email, not public reviews.

### Case studies

- **Instagram 2016:** mocked, then iconic — kept the core glyph shape, chose a look unmistakable on a crowded home screen, doubled down. Lesson: the block icon must be **unmistakable at 32px**; commit.
- **Airbnb Bélo 2014:** mocked, endured — a new symbol needs a consistent system built around it and time, not a reversal.
- **Twitter→X 2023:** rushed, unexplained, continuity-breaking; ratings collapsed. Do the opposite.
- **Craft:** design the full system at once (wordmark, icon-only, one-color, dark mode) from the same square glyph; keep a rollback path.

---

## 4. Town-by-town launch playbook

### Win Saint Joseph completely first (Facebook lesson)

Facebook saturated Harvard (>50% of undergrads in month one) before opening the next school. **Rule: no town #2 until St. Joe shows high penetration and weekly-active depth.** St. Joe + CSB is a dorm-sized closed network — ideal.

### Explicit density/activation thresholds per town

- Borrow Nextdoor's 10-verified/21-day pilot and FPF's 100-residents-go-live as gates. Pick Block Party's number (X verified residents + Y seeded events) and hold to it.
- Below-threshold towns stay in **coming-soon/seed-only mode** so first arrivals never hit a ghost town.

### Seed content before users arrive

- Pre-load Map venue pins, Activities clubs/trails/parks, and Calendar recurring happenings (farmers market, church/college events, city meetings) so day one is populated.
- Today's brief + weather auto-populate from public data — every town has a non-empty home screen from hour one.

### Grassroots tactics a solo founder can run

- **Founding-member recruiting:** 5–10 local leads (librarian, coffee-shop owner, CSB RA, city comms) to seed and vouch — geographic credibility is everything.
- **Real-name / verified-resident onboarding** from day one.
- **Ride utility moments as launch beats:** first snow closure, college move-in week, a town festival.
- **Free per town early** — avoid Meetup's fee-driven death spiral.

---

## Recommendations (staged)

### Phase 1 — Rebrand + brand system (now)

1. Complete the pre-launch identifier purge: ship `Jesse.BlockParty`, create its App Store Connect record, and add the new bundle id to the Google Places key restriction. Persisted keys are now `bp.*` with no migration path — the new bundle id means a new container, so existing installs re-authenticate and re-onboard. **Gate:** venue photography works under the new identifier and the new icon is unmistakable at 32px.
2. Maintain the ink-on-warm-white core with the one plum semantic accent for live/active/selected/primary states. Photography, cartography, weather/utility slabs, and the reference-matched onboarding palette are controlled content/system exceptions. The proposed green/amber/red 3-state palette was not adopted; category stays glyph-led.
3. Rebuild the top three empty states (Today, Activities, Map) as onboarding surfaces: value-named copy, ghost/preview row, one verb-first CTA.

### Phase 2 — Engagement mechanics (before wide launch)

4. SMS-first reminders (2-hour Going nudge, 1-week Maybe nudge), host text blast, who's-coming social proof on event pages.
5. Profile photo/onboarding nudges.
6. No feed in v1; all content oriented to *doing* (events/clubs/trails/parks).

### Phase 3 — Saint Joseph launch (one town)

7. Seed venues (Map), clubs/trails/parks (Activities), recurring events (Calendar) before opening; auto-populate Today + weather.
8. Recruit 5–10 founding leads; verified-resident real-name signup.
9. Set the go-live threshold (X verified residents + Y seeded events) and a pilot window; time launch to a utility moment (move-in week, first snow, a festival).

### Phase 4 — Expansion (only after St. Joe is dense)

10. Replicate seed-then-open town by town; host tooling stays free early.

---

## Benchmarks that change the plan

- Weekly-active-among-verified in St. Joe stalls well below ~60% → fix retention (reminders, seeded freshness) before expanding.
- Negativity/complaint content emerges → tighten categories, add human moderation immediately.
- Rebrand drives a ratings drop → escalate developer responses and in-app explanation.

---

## Caveats

- Partiful's numbers come largely from one CNBC piece citing Sensor Tower estimates and company figures — directionally strong, not audited. The RSVP color mapping and typeface details come from design-system teardowns of the live product.
- FPF's civility stats are member surveys (self-selected respondents) — directional, not independent.
- Nextdoor's 180%/46% profile-photo lifts are company-reported from select-market tests.
- Rebrand mechanics reflect current Apple policy and ASO guidance; verify against App Store Connect rules at execution time.
- Several items carry real ongoing cost for a solo founder (moderation, typeface licensing, SMS delivery) — sequence them; lean on Jost (free Futura alternative) and a phased SMS rollout.
- St. Joe's specific dynamics (CSB/SJU seasonality, town size) shape the thresholds — the numbers above are borrowed benchmarks to calibrate against, not guarantees.
