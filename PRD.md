# Hygge — Product Requirements Document

- **Product:** Hygge (name decided — "Health" dropped)
- **Stage:** Pre-launch
- **Owner / builder:** Jesse (solo, building with Claude Code)
- **First town:** Saint Joseph, MN (~7,000 people)
- **Updated:** July 5, 2026
- **What this doc is:** A PRD ("product requirements document") is just the one page everyone points to that says *what we're building, for whom, and why.* Plain language on purpose — no jargon.

---

## 0. The honest starting point (read this first)

The app you actually built is a **hyper-local community app for St. Joseph** — not a 4-pillar wellness app. This is based on the real code, not the old plan:

- **Everything shipped is the community layer** — a Today timeline, a shared calendar anyone can add to, a live town map, clubs with join/RSVP, a trails directory, a daily quest, and Claude-powered moderation on new posts. It works.
- **Diet, Fitness, and Health-Info have zero code.** No clean-food score, no calorie tracking, no barcode scanner, no guided workouts, no progress rings — none of it exists.
- **Rule going forward: no words without code behind them.** The marketing, the site, and this doc only claim what actually exists. (This is your own "real data only, never inflated" rule, applied to the copy too.)

**You've committed to the community app as the product. Health is dropped. That's the spine of everything below.**

---

## 1. What Hygge is (the one-liner)

> **Hygge is the app for your town. One calm place for everything happening in Saint Joseph — a daily timeline, a shared calendar anyone can add to, a live town map, and real neighbors showing up.**

Belonging is the product, not tracking. Getting outside and showing up to real things *is* the health outcome. Tagline stays the honest one already in your code: **"Your town, every day."**

---

## 2. Why this, why now

Every big health app is **lonely and placeless by design.** MyFitnessPal is a spreadsheet. Whoop is a private data cockpit. Strava is a global leaderboard of strangers. Noom monetizes your anxiety. None of them know Saint Joseph exists, and none of them can — knowing your town would make them a different company.

That's the gap. **Hygge is the only "town" app people open like a health habit — and the only "health" app that is a *place*.** A solo builder can't out-database MyFitnessPal or out-sensor Whoop, but you *can* own one small town so completely that no global app can follow you into it. That's the whole bet.

---

## 3. Who it's for

Three people matter, and they do different jobs. Don't blur them — blurring them is how town apps die.

### Primary user → "Maren, 29" — the St. Joe returner
Grew up in or near St. Joe, went to CSB/SJU or the local high school, now back in town (teacher, nurse, young parent, works at a local shop). Has an iPhone, isn't a "fitness app person." Knows a few people but not the whole fabric anymore. **Wants to feel rooted and gently move more.** Her real problem: she doesn't find out what's happening until it's over, because the info is scattered across Facebook groups, a church bulletin, and a coffee-shop chalkboard.

**Why Hygge wins her:** her actual town is the content. A ten-second scan of what's on tonight, a Tuesday walk framed as "come hang," Jesse's real face behind it. **Optimize the whole app for Maren's repeat opens.**

### Acquisition channel → "Dana, 44" — the community connector
The coffee-shop owner, the run-club organizer, the church youth-group lead — a high-connectivity local whose adoption drags dozens of people in behind her. Her pain isn't calories; it's that her events are invisible and turnout is a coin flip. **Hygge is a free megaphone aimed at exactly her audience.** You hand-recruit a handful of Danas *before* launch so Maren lands on a board that's already alive. There are only a few Danas per town — court them, don't count on scaling on them.

### Marketing narrative → "the Noom refugee"
Burned by streaks, paywalls, fake "coaches," and auto-billing. Loves the "finally an honest one" story. **Great for TikTok and press, bad for your launch numbers** — most of them don't live in St. Joe. Use their story to get attention; don't build for them.

---

## 4. Where we win (positioning)

I looked at the real 2026 field and pricing. Short version: **don't fight on tracking.** An AI calorie scanner and progress rings are table stakes now — building them buys a seat at the table and nothing more (which is why **rings are cut**, see §5).

| App | What it's great at | The gap Hygge exploits |
|---|---|---|
| **MyFitnessPal** ($19.99/mo) | Deepest food database; it's a verb | A cold global spreadsheet with no sense of place or people |
| **Noom** ($17–70/mo) | Behavior-change story, huge ad budget | Dark patterns, cancellation traps, fake coaches — the *anti-Hygge*, loudly |
| **Whoop** ($199+/yr) | Best passive recovery data | Expensive hardware for a narrow tribe; totally solitary |
| **Strava** ($11.99/mo) | Real social fitness; *closest competitor* | Community is activity-shaped, not town-shaped; comparison fatigue |
| **Apple Health/Fitness+** (free/$9.99) | Free, pre-installed, owns the sensors | Deliberately generic; will never know or care about St. Joe |

**The wedge:** Hygge is a live map of St. Joseph, a calendar anyone can post to, a run club on real streets, and a real founder standing behind it. **Belonging retains where guilt churns.**

⚠️ **The one live threat is Strava.** It already speaks "local community" and could bolt a town feed onto its network faster than anyone. So your locality has to be so specific, warm, and native-to-St.-Joe that a global sport app can't credibly follow. *(Note the tension with the new coral-on-white look in §7 — keep the voice cozy so you don't just become a quieter Strava.)*

---

## 5. The product

### 5a. What's already built (keep it)
Today timeline · shared calendar · add-a-post (event / club / trail, with photo + Claude moderation) · live town map with venue pins · clubs (join/leave, member counts) · event RSVPs · trails directory · daily quest · admin approval queue · email/password sign-in. **This is a real, working community app.** The job now is to sharpen it and give it a soul.

### 5b. The three hero features to build next
The "text a screenshot to a friend" moments. All three reuse things you've *already built.*

1. **Porchlight — a live "who's out right now" map layer.**
   Open the map at 4pm and a few soft coral porchlights glow on real buildings: *"Maren + 2 at Local Blend,"* *"pickup run leaving Millstream in 20."* Named neighbors who tapped "I'm here, come say hi." The glow fades on its own after 2 hours. No competitor can do this — Strava shows where people *were*, never a live open door in your town. *(Buildable: a self-expiring row lit by the map's existing live-glow pipeline.)*

2. **Streetlight roll call — the anti-streak.**
   Instead of "🔥 47-day streak, don't break it," Hygge shows *"St. Joe showed up 9 times this week."* A number that can only go up and **isn't yours** — nothing to lose, no guilt. The surface reads: *"No streaks to break. No guilt. Just the town, showing up."* This puts the "compound" idea on the *town's* momentum, not a fragile personal chain. *(Buildable: a reskin of RSVP + quest counts you already compute.)*

3. **The town's tonight-page.**
   The top of Today reads *"Tonight in St. Joe: trivia at the brewery 8pm · 6 going · farmers-market walk tomorrow 9am."* The thing a group chat actually pastes — the daily-open habit that makes Hygge a utility, not an optional cozy toy. *(Buildable: a curation pass on live data you already have.)*

### 5c. The Health-Info pillar, resolved → "The Daily Almanac" ✅ building it
The blank health pillar becomes **one calm, admin-written daily card** that reads out *this town's real day* and turns it into one low-bar outdoor nudge:

> *"Sun's up till 8:58 — 20 quiet minutes outside beats any screen tonight. The Lake Wobegon Trail is clear and 62°."*

It uses live St. Joe weather + sunrise/sunset. **No sensors, no calorie table, no HealthKit, no content licensing** — you write one short line a day, the same muscle as the daily quest. Sunlight, seasons, and getting outside is the perfect *hygge* health primitive, and the payoff is always a real trail or event — so the health pillar *feeds* the community pillar instead of splitting the app's soul.

### 5d. Diet, Fitness & progress rings → cut
- **Not building diet/fitness pillars.** You can't out-database MyFitnessPal or out-sensor Whoop solo, and a worse copy dilutes the one thing that's actually different.
- **Progress rings are removed.** ✅ They're table stakes Apple owns for free, and they pull the app toward the "data cockpit" feeling Hygge is defined against. The **Streetlight roll call** (the town's count, not yours) replaces any sense of "progress."

---

## 6. Pricing → **$2/month, with a 7-day free trial** ✅ decided

Hygge is a **$2/month subscription** — "less than a cup of coffee at Covenant Cup." It's already the copy in your repo landing (two places), and it radically undercuts every incumbent (MyFitnessPal $19.99, Noom $17–70, Strava $11.99). At that price it reads as a **trust signal — "this is the town's, not a VC extraction machine"** — not a growth hack.

**Make the $2 feel like belonging, not a paywall:** frame it as *"$2/month keeps St. Joe's events free"* — the money visibly comes back to payers as real town events. That's membership in the town, not a subscription to software, and it's perfect founder-story content ("your $2 helped fund the Thursday bonfire").

**Two honest things to hold (kind version, from the research):**
- A paywall on a brand-new single-town app can slow the one thing that matters most early: getting a real chunk of the town on the board. **The 7-day free trial is the answer** — a neighbor gets a full week to see a live board (and ideally show up to one real thing) before the first $2 charge, so price never blocks that first taste. Keep the trial honest: easy to cancel, a clear reminder before it bills — the opposite of the Noom trap.
- There is **no payment code yet** (no Stripe/RevenueCat). The $2 is copy only until billing is built — so charging is a build task, not a decision that's already live (see §11).

---

## 7. Brand, voice & name

- **Visual identity — updated July 5:** the accent is now **coral on white backgrounds — cleaner and brighter, closer to Strava** than the old sand/slate cozy palette. Coral is reserved for live/tappable things (porchlights, primary buttons); everything else stays quiet on white. *(The earlier "slate blue + sand + charcoal" palette is superseded.)*
  - **One thing to hold onto:** the *look* is getting brighter, but the *voice* must stay cozy and neighborly — warm copy, no comparison, no shame. That's what keeps you the un-intimidating one instead of just a quieter Strava.
- **Voice:** a neighbor, not a brand. Warm, calm, hyper-local. **No badges, streaks, feeds, or notification spam. Real data only — never seeded or inflated counts.**
- **The founder is the channel, not a mascot.** Start build-in-public content *now*: short vertical videos of the actual build, of St. Joe itself, of the "why." The CTA is never "download" — it's "if you're in St. Joe, comment your name." That doubles as your waitlist and your proof of demand. Keep Jesse's face on the onboarding screen.
- **Name — decided: "Hygge."** "Health" dropped. The leftover "Joetown" wordmark on the login screen has been changed to "Hygge," so the app now has one consistent name anchored to "Saint Joseph, MN."

---

## 8. Success metrics (measure density, not downloads)

- **% of St. Joseph reached** (toward a goal like "get St. Joe to 1,000"), **not** raw installs.
- **Weekly repeat opens by Marens** (does the returner come back?).
- **Real events posted per week** and **average RSVPs per event** (is the board alive?).
- **# of active Danas** posting (is the channel seeded?).
- **Trial→paid conversion** once billing ships (will the town actually pay $2?).
- Vanity metrics to explicitly ignore: total signups, streak counts, anything inflatable.

---

## 9. Risks & the failure mode to design against

- **The empty-calendar death spiral (the big one).** With no streaks or notifications by design, a bare board on a slow week has nothing to pull anyone back. **Mitigation:** recruit Danas *before* asking Marens to show up, and use "$2 keeps events free" money to fund events so the calendar is never empty. Load-bearing, not optional.
- **The $2 paywall vs. saturation.** Charging before the board is alive can stall the town-filling flywheel. Watch trial→paid closely; keep the free trial generous.
- **Founder-bandwidth ceiling.** Growth tied to Jesse's face and time doesn't transfer to town #2. Batch-film content; design a repeatable "local builder" pattern early.
- **Strava bolts on a town feed.** Answered only by being unbeatably native to St. Joe — and by keeping the *voice* cozy even as the palette brightens.
- **Trust drag right now.** The deployed site still sells the abandoned diet app — fix before any real marketing push (see §11).
- **Moderation at scale.** Today it's a single-admin allowlist + Claude moderation. Fine for launch; needs a plan before town #2.

---

## 10. Decisions locked this session (July 5)

- ✅ **Community is the product.** Diet/fitness will not be built as pillars.
- ✅ **Name = "Hygge"** ("Health" dropped; "Joetown" removed from code).
- ✅ **Pricing = $2/month subscription.**
- ✅ **Health-info pillar = the Daily Almanac.**
- ✅ **Progress rings removed.**
- ✅ **Fix the live site** so it stops selling a product that doesn't exist.
- ✅ **Visual direction = coral accent on white backgrounds** (Strava-clean), voice stays cozy.
- ✅ **7-day free trial** before the first $2 charge.
- ✅ **Coral applied in code** — the shared accent token now drives coral on every screen (buttons, active tabs, RSVP fills, key icons) and the shadcn components.

**Still genuinely open:** whether the blue location links should also go coral (kept blue for now — better text contrast); the moderation plan before town #2; verifying the coral look on the simulator.

---

## 11. Build order for Claude Code (v1)

1. **Fix the live site (urgent, mostly a redeploy).** Your repo landing is already correct and already $2/mo — the deployed Vercel site is just a **stale old build** still showing the diet app. Rebuild + redeploy (`npm run site:build`, then deploy to Vercel) so the deployed site matches the real product. This is what "take away words with no code behind them" means for the site.
2. **Streetlight roll call** — cheapest hero; mostly copy + aggregating counts you already have.
3. **The Daily Almanac** — reuse the daily-quest admin pattern + existing sunrise/sunset data.
4. **Tonight-page** — hero-framing pass on the Today tab.
5. **Porchlight** — the live "who's out" layer on the map.
6. ✅ **Coral recolor — done** — applied at the token level (`theme.ts` + `tailwind.config.js`), so every screen and the shadcn components render coral on white in one shot. Just needs a simulator eyeball.
7. **Real user profiles + founder onboarding** (Jesse's face + story).
8. **$2/month subscription billing** — add Stripe or RevenueCat (+ App Store rules) with the **7-day free trial**. This is the piece that lets you actually charge; there's no payment code today.

## 12. Out of scope for v1 (punted, on purpose)
Diet/fitness/health tracking pillars · progress rings · biometrics & HealthKit · multi-town expansion · town-records leaderboard · post-event photo wall · "who's-working-out-now" · invite-only gating of St. Joe.
