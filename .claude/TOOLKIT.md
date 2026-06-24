# TOOLKIT — what to reach for, when

A plain-language map of the Claude tools installed for this project, tuned to the
**St. Joe community page** (see `../CLAUDE.md` → Product & principles, and the
project memory: `product-vision`, `on-brand-bar`, `definition-of-done`).

You invoke a skill by typing `/<name>` or just asking for it by name. Don't
memorize this — skim it when you're starting a task and unsure what to use.

---

## 0. Keep Claude on-vision (use these first)

| Want | Reach for |
|------|-----------|
| Claude to remember your intent across sessions | The **memory** files in `~/.claude/projects/-Users-owner-my-business/memory/` — already holds your vision, target user, on-brand bar, done-bar. Ask me to "remember X about St. Joe" to add more. |
| Tighten the project rules Claude follows | `/claude-md-improver` (audit `CLAUDE.md`) or `/revise-claude-md` (fold in this session's learnings) |
| Think through a fuzzy idea before building | `/brainstorming` (superpowers) — one question at a time, turns an idea into a clear plan |

---

## 1. Design & build the community UI

The community app's in-product screens (Today / Clubs / Letter / Hello) are
**multi-step product UI**, so:

| Want | Reach for |
|------|-----------|
| Distinctive, intentional UI that isn't templated | `/frontend-design` or `/ui-ux-pro-max` (palettes, type pairings, components) |
| Polish/critique/harden an existing screen, iterate live in browser | `/impeccable` (args: `craft`, `audit`, `polish`, `clarify`, `bolder`…) |
| The **marketing landing page** to stand out | `/design-taste-frontend` (taste-skill) — built for landing pages/portfolios. ⚠️ NOT for dashboards or multi-step product UI — use the row above for in-app screens. |
| Turn a mockup image into code | `/image-to-code` (taste-skill) |
| React/Next.js component & state patterns | `/frontend-patterns` (everything-claude-code) |

> On-brand guardrail: whatever you use, hold the result to the **on-brand bar**
> (calm, warm, neighborly — not corporate, not busy). Tell the design skill that
> up front; don't let it add badges/streaks/feed mechanics.

---

## 2. Database & auth (Supabase)

| Want | Reach for |
|------|-----------|
| Anything Supabase — auth, RLS, migrations, queries, Edge Functions | `/supabase` |
| Make a Postgres query/schema fast & correct | `/supabase-postgres-best-practices` |
| Backend/API structure for a new feature | `/backend-patterns` or `/api-design` (everything-claude-code) |

Community tables live in `supabase/migration-community.sql` (clubs / club_members
/ club_events / event_rsvps, `is_admin()` RLS). Always use `localDate()` from
`lib/db.ts` for dates.

---

## 3. Ship it (Vercel + preview)

| Want | Reach for |
|------|-----------|
| See a change actually working before claiming done | the **preview tools** (start server → reload → snapshot/screenshot). This is the done-bar. |
| Deploy | `/vercel:deploy` (add `prod` for production) |
| Manage env vars / secrets | `/vercel:env` |
| Check deployment status | `/vercel:status` |
| Run the app locally to eyeball it | `/run` |

---

## 4. Launch & grow the community tier (your flagship)

`marketing-skills` is a 44-skill founder toolkit — start here, but **filter
everything through the on-brand bar** (skip popups/streaks/aggressive growth
hacks that read as corporate).

| Want | Reach for |
|------|-----------|
| Nail positioning & who it's for (do this first) | `/product-marketing` |
| Plan the St. Joe launch / go-to-market | `/launch` (Owned→Rented→Borrowed channels; owned = email/word-of-mouth fits a hyper-local town) |
| Understand your neighbors as users | `/customer-research` |
| Write warm, non-corporate copy | `/copywriting` + `/copy-editing` |
| Improve signup / onboarding without friction | `/onboarding`, `/signup` |
| App-store listing later | `/aso` |

---

## 5. Quality, correctness & safety

| Want | Reach for |
|------|-----------|
| Review the current diff for bugs/cleanups | `/code-review` (or `/simplify` for quality-only) |
| Confirm a fix actually works in the app | `/verify` |
| Debug something broken, methodically | `/systematic-debugging` (superpowers) |
| Build a feature test-first | `/test-driven-development` or `/tdd-workflow` |
| Security pass before launch | `/security-review` |

---

## Notes / overlaps (so you don't get lost)

- **Design skills overlap.** Rough call: `frontend-design`/`ui-ux-pro-max` for
  in-app screens, `impeccable` for polishing/iterating, `taste-skill` for the
  marketing landing page. Any of them works — pick one and go.
- **`article-writing` exists in two plugins** (everything-claude-code +
  marketing-skills). Use the marketing one for launch/growth content.
- **`everything-claude-code` also has investor/market-research skills** — ignore
  unless you start fundraising.
- **Antigravity note:** these all work because you run **Claude Code inside
  Antigravity**. Antigravity's own Gemini agent does NOT read this file or your
  `.claude` config — use Claude Code for anything that must stay on-vision.
