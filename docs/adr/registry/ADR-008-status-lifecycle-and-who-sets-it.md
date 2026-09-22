# ADR-008 — Status lifecycle, and who is allowed to set it

**Status:** Accepted
**Date:** 2026-09-22

## Context

Agents are good at finding candidate sources and bad at judging which ones should be
speaking to a town on Block Party's behalf. If an agent can make a source live, then a
plausible-looking page found at 2am starts publishing to users with nobody having
looked at it.

Separately, sources go quiet — seasonally, or because a business closed. Deleting them
loses the record of why they were ever there, and invites the next agent to re-add the
same dead source next month.

## Decision

An entry's `status` is one of **`proposed` | `active` | `paused` | `retired`**.

- **`proposed`** — not live; the runner ignores it. **This is the only status an agent
  may set**, and it is the default when `status` is absent.
- **`active`** — live, read on every run. **Only Jesse sets this.**
- **`paused`** — temporarily skipped: seasonal, or the site is down for weeks.
- **`retired`** — permanently out of use.

**Entries are never deleted.** A dead source is set to `retired` with a line in `Notes:`
saying why.

An optional **`added_by`** records provenance: `jesse`, or `agent:<name>`.

## Consequences

- An agent can do the legwork — research, propose, write the notes — without being able
  to put anything in front of a user. The review step is a status flip.
- The registry accumulates proposed entries that may never be promoted. That is cheap;
  the runner skips them.
- History is preserved: a retired entry explains itself, and stops the same dead source
  being rediscovered and re-added.
- `added_by` makes it possible to audit what the agents have been proposing, which
  matters the first time one proposes something wrong.
