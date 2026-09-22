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

The decisions behind every rule here live in [`docs/adr/`](../docs/adr/). ADRs are immutable;
when a decision changes, a new ADR supersedes the old one, and the old one is never edited
(ADR-005).

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
| `sources` | yes | List of places to look. At least one. |

### Source fields (`sources[]`)

| Field | Required | Meaning |
| --- | --- | --- |
| `url` | yes | The URL to read, or the literal `TODO` when it is not known yet. **Never invent a URL** — a guessed URL scrapes a stranger's site under a local business's name (ADR-007). An `active` entry may not carry a `TODO` url. |
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

---

## Rules

- **Only `place_id` persists from Google Places.** Names, hours, photos, ratings and reviews
  from a Places response must not be copied into these files — Places terms of service
  prohibit storing them. Look them up live instead (ADR-001).
- **Always append `MN` to St. Joseph searches.** Any web search for a St. Joseph source
  includes "MN"; without it, results are St. Joseph, Missouri and St. Joseph, Michigan
  (ADR-006).
- **`stjosephmn.gov` and `joetownmn.com` block robots.** Their `robots.txt` disallows
  automated fetching, so both use `method: search_snippet` and are never fetched directly.
  If another site starts returning a robots refusal, switch that source to `search_snippet`
  rather than working around the block (ADR-001, ADR-009).
- **One file per town**, named `sources/<town>-mn.md` (ADR-006).
- **Registry lives at the repo root**, in this folder. The Android repo and the waitlist repo
  link here instead of keeping their own copies (ADR-004).
- **Runners default to dry-run.** Writing to production requires an explicit `--write`
  (ADR-009).
- **Run `sources/validate` after every edit.** It is instant, and it is the only thing between
  a typo and a broken 6am run.

---

## Glossary

| Term | Meaning |
| --- | --- |
| **Registry** | This folder. The whole set of town files — the human-owned answer to "where does Block Party look, and how". |
| **Entry** | One place in a town file: a `## Name` heading plus its yaml block. Identified forever by its `id`. |
| **Source** | One item in an entry's `sources` list — a single URL plus how to read it. An entry can have several. |
| **Runtime state** | What happened when a source was last read: `last_checked`, `last_hash`, `last_error`. Lives in the Supabase `sources` table, never in these files (ADR-002). |
| **Sync** | The one-way copy of registry fields from these md files into the database at the start of a run. If the two disagree on a registry field, the md wins (ADR-002). |
| **Snapshot** | The saved text of a source at the moment it was read, written only when its hash changed. Dry-run snapshots go to `.runs/`, which is gitignored (ADR-009). |
| **Dry-run** | A run that fetches for real but writes nothing to production. The default (ADR-009). |

---

## Deprecated keys

None yet. When a key is replaced, it is listed here with its replacement and the date — the
key itself is never renamed or reused (ADR-007).
