# ADR-007 — Entry format: heading, yaml, notes — and the schema is additive only

**Status:** Accepted
**Date:** 2026-09-22

## Context

The registry has to be readable and editable by both a person and an agent. Pure prose
cannot be validated; pure structured data (JSON, a database table) loses the quirks that
make a source workable — "this site returns 406 to curl", "the https version refuses the
connection", "this calendar covers two campuses". Those notes are the difference between
a source that works and one that silently rots.

The format also has to survive years of additions. Every new field cannot mean a
migration, and a field written in 2026 has to still mean the same thing in 2030.

## Decision

An entry is a **`## Name` heading, a fenced `yaml` block, and an optional freeform
`Notes:` section** that is never parsed. A town file starts with frontmatter carrying
**`schema: 1`**.

**Required:** `id` — a permanent slug that **never changes**, not even when the business
renames or moves — and `sources[]` with at least one entry carrying a `url` and a
`method`. Everything else is optional.

**Unknown keys are allowed.** Sync stores any key it does not recognise in a jsonb
`extra` column, so recording something new never needs a migration.

**The schema is additive only.** A key is never renamed and never repurposed. A key that
turns out to be wrong is superseded by a new key, and the old one is listed as deprecated
in `sources/README.md`.

**A URL is never invented.** Unknown means `url: TODO`.

## Consequences

- Anyone can add information immediately, without a schema change and without asking.
- The parser stays small: heading, fence, done. Notes cost nothing to write and are
  never a parse risk.
- Old entries keep meaning what they meant. The price is keys that outlive their
  usefulness and sit deprecated rather than being cleaned up.
- A guessed URL would point the runner at a stranger's site under a local business's
  name. `TODO` is always the correct answer to "I could not find it", and a validator
  rejects an active entry that still carries one.
- `schema: 1` gives a version to bump if the format ever has to break. Until then, every
  file declares it.
