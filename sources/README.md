# Source registry

This folder is the list of **where Block Party gets local information and how to get it**.
One file per town: `sources/<town>-mn.md`. The `-mn` suffix is mandatory (ADR-006) — it is
the reason St. Joseph, Minnesota never gets confused with St. Joseph, Missouri.

These files own **what and how**: places, URLs, method, trust, quirks. They are written by
Jesse or by an agent, and never by a script. Runtime state — when a source was last checked,
what it hashed to, what error it returned — lives in the Supabase `sources` table and is
written only by a runner. Sync is one-way, md → DB, at the start of every run (ADR-002).

If you are about to write a timestamp, a hash, or an error message into a file in this
folder: stop. That belongs in the database.

---

## The rule (ADR-010)

**Completeness is the goal, not convenience.** The target is *every* business,
institution and public-benefit place in the town — churches, parks, trails, the library,
the food shelf and city services included, not businesses alone. Not the ones with good
websites. Not the ones we happen to know. A place with no website and no social media is
still a place a neighbour needs, and its absence from this registry is a **defect**, not
a limitation. A hard-to-reach place gets a harder method, never a quiet omission.

**Coverage is measured against an external count of what exists**, never against what we
have already collected. The question is not how many entries we have; it is how many
places exist that we do not have.

**Freshness is part of correctness.** A stale entry is a wrong entry. Every entry carries
a cadence (ADR-011) and a last-verified date, and one past its cadence is reported as
stale rather than served silently as current.

**The whitelist still holds.** The daily routine reads only this registry and does not
crawl (ADR-001). Discovery makes the whitelist bigger; it does not make it open.

Two thirds of St. Joseph has no website — measured, 23 of 69 named places. That third is
not the town. Closing the rest is outreach, not scraping.

The decisions behind every rule here live in [`docs/adr/registry/`](../docs/adr/registry/),
named `ADR-NNN-kebab-slug.md` and numbered from 001 in their own series, separate from the
app's ADRs in `docs/adr/`. ADRs are immutable; when a decision changes, a new ADR supersedes
the old one, and the old one is never edited (ADR-005).

---

## Entry format (ADR-007)

A town file is YAML frontmatter, then one entry per place. An entry is a `## Name` heading,
a fenced `yaml` block, and an optional freeform `Notes:` line that is never parsed.

````md
---
schema: 1
town: st-joseph-mn
---

## Krewe
```yaml
id: krewe
status: active
place_id: ChIJxxxxxxxxxxxxxxxxxxxxxxx
category: restaurant
partner: true
added_by: jesse
sources:
  - url: https://example.com/events
    kind: website
    method: fetch
    trust: official
```
Notes: freeform. Quirks, why this source is here, who to talk to.
````

**Required:** `id`, and at least one entry in `sources` with a `url` and a `method`.
Everything else is optional.

**Unknown keys are allowed.** Adding new information is always fine — `hours:`, `contact:`,
`logo:`, anything. Sync stores keys it does not recognise in the `extra` jsonb column, so no
migration is needed to record something new (ADR-007).

**Additive only.** Never rename or repurpose an existing key. If a key turns out to be wrong,
add the new key and list the old one under [Deprecated keys](#deprecated-keys) below. That is
what keeps an entry written in 2026 readable in 2030.

`schema: 1` in the frontmatter is the format version. A file without it is invalid.

---

## Field reference

### Entry fields

| Field | Required | Meaning |
| --- | --- | --- |
| `id` | yes | Permanent lowercase slug. **Never changes**, not even if the business renames or moves. It is the join key to the database and to the run history (ADR-007). |
| `status` | no (defaults to `proposed`) | Lifecycle state. See [status values](#status-adr-008). |
| `place_id` | no | Google Places place ID. The **only** field that may be persisted from a Places response (ADR-001). |
| `category` | no | Freeform bucket — `restaurant`, `cidery`, `bakery`, `gov`, etc. Not an enum; used for grouping, not logic. |
| `partner` | no | `true` when the business is a Block Party partner. Absent means not a partner. |
| `added_by` | no | `jesse` or `agent:<name>` (e.g. `agent:claude`). Says who proposed the entry (ADR-008). |
| `tier` | no (defaults to `listed`) | What the entry is *for*, and how often it is checked. See [tier values](#tier-adr-011). |
| `aka` | no | Other names this place is known by. Discovery treats them as already held, so the same place stops being proposed under a second name every month. This is how a human settles "Kennedy Elementary is Kennedy Community School" permanently — no rule can work that out. |
| — | — | *Roster-side twin:* discovery's per-town `aliases` list folds two **candidate** names into one before either becomes an entry (Sal's Bar / Sal's Bar and Grill). `aka` settles a candidate against an entry that already exists; `aliases` settles two candidates against each other. |
| `place_type` | no | `Business`, `Community group`, `Church`, `School / college`, `Government` or `Park / historic`. Set by verification so "businesses only" is a filter, not a second list. |
| `address`, `phone` | no | Where the place is and how to reach it, from a non-Google source only (ADR-016). Verification's drafts fill them in. |
| `entity` | no (defaults to `place`) | What kind of thing this is. The registry lists **places**; events live in their own table and are what a place's sources produce (ADR-013). |
| `sources` | yes | List of places to look. At least one. |

### Source fields (`sources[]`)

| Field | Required | Meaning |
| --- | --- | --- |
| `url` | yes | The URL to read, or the literal `TODO` when it is not known yet. **Never invent a URL** — a guessed URL scrapes a stranger's site under a local business's name (ADR-007). An `active` entry may not carry a `TODO` url **when its `method` is `fetch` or `api`** — those mean "go and read this", and there is nothing at TODO to read. A `submission` source may carry `TODO` at any status: it is never read, and two thirds of this town has no website (ADR-015). |
| `method` | yes | How this source is read. See [allowed values](#allowed-values). |
| `kind` | no | What kind of thing the URL is. |
| `trust` | no | How much one mention from this source is worth. |

---

## Allowed values

### `method`

| Value | Meaning |
| --- | --- |
| `fetch` | The runner requests the URL directly and hashes the result. |
| `search_snippet` | The runner cannot fetch it — an agent answers with a web search instead, restricted to that site where possible. Used when a site blocks bots. |
| `submission` | The information arrives from a human submission, not from reading the URL. Not fetched. |
| `api` | Read through a structured API rather than a page fetch. Not yet handled by the runner. |

### `trust` (ADR-001)

| Value | Meaning |
| --- | --- |
| `official` | The place's own channel or a government channel. **One mention is enough to publish.** |
| `squishy` | Secondhand — a community page, an aggregator, someone else's post. **Needs two or more independent mentions** before it publishes. |

### `kind`

`website` · `instagram` · `facebook` · `ical` · `rss` · `gov`

### `status` (ADR-008)

| Value | Meaning |
| --- | --- |
| `proposed` | Not live. The runner ignores it. **This is the only status an agent may set.** |
| `active` | Live. Read on every run. **Only Jesse sets this.** |
| `paused` | Temporarily skipped — seasonal business, site down for weeks. |
| `retired` | Permanently out of use. |

**Never delete an entry.** Set `status: retired` and say why in `Notes:`. A deleted entry takes
its history with it; a retired one explains itself two years later (ADR-008).

### `tier` (ADR-011)

`status` says whether the runner may read an entry. `tier` says what it is for. They are
independent — a `listed` entry can be `proposed`, `active`, `paused` or `retired`.

| Value | What it is | Publishes | How it is promoted | Cadence |
| --- | --- | --- | --- | --- |
| `watched` | A real URL whose content changes — events, hours, announcements | yes | per entry, by Jesse | every run |
| `listed` | The place exists: name, location, category. Nothing to fetch | no | **batch, by category** | re-verified quarterly |
| `submitted` | No web presence; the owner tells Block Party directly | yes | per entry, by Jesse | when something arrives |

`listed` is what makes batch approval safe: it is *defined* by publishing nothing, which
is the exact property ADR-008 was protecting. The worst case for a bad `listed` entry is
a wrong pin on a map — visible, and cheap to fix.

An entry moving from `listed` to `watched` crosses the publishing line, so it needs
per-entry review even if it was originally batch-approved. Discovery flags those; it does
not re-tier on its own.

---

## Rules

- **Only `place_id` persists from Google Places.** Names, hours, photos, ratings and reviews
  from a Places response must not be copied into these files — Places terms of service
  prohibit storing them. Look them up live instead (ADR-001).
- **Always append `MN` to St. Joseph searches.** Any web search for a St. Joseph source
  includes "MN"; without it, results are St. Joseph, Missouri and St. Joseph, Michigan
  (ADR-006).
- **Robots claims are measured, not asserted (ADR-012).** Before an entry is set to
  `search_snippet` because "the site blocks robots", read the robots rule and record it.
  `stjosephmn.gov` was marked blocked for weeks and is not — its robots.txt blocks
  `/admin`, `/search`, `/map` and `/currentevents`, and nothing else. That mistake cost
  the registry the city's calendar feeds until 2026-09-23. `joetownmn.com` does block and
  stays `search_snippet`. `stjosephchamber.com` returns **403 to any non-browser client**,
  so robots.txt cannot even be read — that is a server refusing us, not a robots rule, and
  retrying with a browser user-agent to get past it is forbidden.
  `mblsportal.sos.mn.gov` (Minnesota Secretary of State filings) has `Disallow: /` for
  every agent (measured 2026-10-04): never fetched; filings count only as search snippets.
- **A 403 usually means "slow down", not "go away" (ADR-014).** `stjosephchamber.com` was
  written off as blocking us and is not: it serves our honest bot user-agent HTTP 200 and
  **403s a Chrome user-agent**, which is an anti-scraper rule, not a wall. Its robots.txt
  has no `Disallow` at all — it asks only for `Crawl-delay: 10`, and every 403 we saw was
  it asking us to slow down while we ignored that. Obey `Crawl-delay`, count reading
  robots.txt as a request, back off and retry on a 403, and only then call a source
  blocked. Impersonating a browser stays forbidden and is also the approach that fails.
- **Getting in is not the same as being able to read it.** The chamber page renders its
  member list client-side; the members are on the 22 category pages. Access and
  readability are two problems and both need solving before a source counts.
- **Prefer a feed to a page (ADR-012).** Where a site publishes iCal or RSS, that is the
  source. An HTML page that renders its content in JavaScript is not a source at all — the
  snapshot will be filter chrome. Find the feed, or fall back to `search_snippet`.
- **One file per town**, named `sources/<town>-mn.md` (ADR-006). Every other `.md` in this
  folder is read as a town file too, unless `scripts/registry.py` skips it by name (it skips
  `README.md` and `CONTEXT.md`). Put new docs elsewhere, or add them to that list.
- **Registry lives at the repo root**, in this folder. The Android repo and the waitlist repo
  link here instead of keeping their own copies (ADR-004).
- **Runners default to dry-run.** Writing to production requires an explicit `--write`
  (ADR-009).
- **Run `sources/validate` after every edit.** It is instant, and it is the only thing between
  a typo and a broken 6am run.
- **Measure coverage with `sources/discover`, not by counting entries.** ADR-010 measures
  against an external roster — Overture, OpenStreetMap, a Google Maps sweep and the local
  directories — so the number that matters is how many places exist that the registry
  does not have. A town is its ZIP codes (ADR-019); duplicates merge only on certainty
  (ADR-018).
- **Then `sources/verify` decides what is open** and writes the drafts, the retire list
  and the outreach list. A place only Google knows needs a non-Google source before it
  is proposed (ADR-016); a place is the organisation, not the building (ADR-017). Agents
  write `proposed` entries only; promoting and retiring stay with Jesse (ADR-008). The
  `town-discovery` and `town-verify` skills are the playbook.

---

## Glossary

The registry's words — Registry, Entry, Source, Place, Town, Discovery, Verification,
Verdict and the rest — are defined in [`CONTEXT.md`](CONTEXT.md).

---

## Deprecated keys

None yet. When a key is replaced, it is listed here with its replacement and the date — the
key itself is never renamed or reused (ADR-007).
