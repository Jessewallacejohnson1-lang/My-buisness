# ADR-011 — Tiers set what an entry is for, and how often it is checked

**Status:** Accepted
**Date:** 2026-09-23
**Depends on:** [ADR-010](ADR-010-completeness-is-the-goal.md)

## Context

ADR-010 commits the registry to every public-benefit place in town, which is roughly
150–200 entries against the twelve it held. Those entries are not alike in any way that
matters to a runner.

A cidery's events page changes weekly and is the whole reason the registry exists. A
gas station's location has not changed since it was built and never will. Reading both
on the same schedule is either far too often for one or far too rare for the other, and
a single `status: active` flag cannot express the difference — `active` says the runner
should read it, not how often or what for.

There is also a third kind, and it is the majority: the two thirds of St. Joseph with no
website at all (ADR-010). Those places have nothing to read on any schedule. Modelling
them as a fetch that always fails would fill every report with noise and bury the real
failures.

Trust (ADR-001) does not answer this either. Trust is about whether a mention is good
enough to publish. This is about what an entry is *for*.

## Decision

Every entry carries a **`tier`**, one of `watched` | `listed` | `submitted`. It is an
optional key, and the schema is additive (ADR-007), so existing entries stay valid and
an absent tier is read as `listed`.

| Tier | What it is | Publishes | Promotion | Cadence |
| --- | --- | --- | --- | --- |
| `watched` | A real URL whose content changes — events, hours, announcements | yes | per entry, Jesse | every run |
| `listed` | The place exists; name, location, category. Nothing to fetch | no | batch by category, Jesse | re-verified quarterly |
| `submitted` | No web presence. The owner tells Block Party directly | yes | per entry, Jesse | when something arrives |

**Cadence is a property of the tier, not of the entry**, unless an entry overrides it.
A `watched` entry read on the 6am routine, a `listed` entry re-verified once a quarter,
a `submitted` entry touched only when a human sends something.

**Past its cadence is a reportable state.** An entry whose last verification is older
than its cadence allows is reported as stale. It is not silently treated as current, and
it is not treated as a failure either — nothing is broken, it is simply old.

**Tier and status are independent.** `tier` says what an entry is for; `status`
(ADR-008) says whether the runner may read it. A `listed` entry can be `proposed`,
`active`, `paused` or `retired` like any other.

## Consequences

- The 6am routine gets faster and quieter as the registry grows, because growth lands
  almost entirely in `listed`, which it does not fetch.
- `listed` is the tier that makes ADR-010's batch approval safe: it is defined by
  publishing nothing, which is exactly the property ADR-008 was protecting.
- An entry can be promoted from `listed` to `watched` when a place builds a website.
  That promotion crosses the publishing line, so it needs per-entry review even though
  the entry was originally batch-approved. Discovery must flag these rather than
  re-tiering them on its own.
- A quarterly re-verify on ~150 entries is a real fetch budget four times a year. It
  stays polite at the existing worker count and does not belong on the daily run.
- Three tiers is a guess. If `listed` splits — say, civic places wanting a different
  cadence from shops — that is a new ADR, not an edit to this one (ADR-005).
