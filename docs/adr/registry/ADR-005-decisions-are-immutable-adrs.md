# ADR-005 — Decisions are immutable ADRs; supersede, never edit

**Status:** Accepted
**Date:** 2026-09-22

## Context

The expensive question about a rule is not what it says — that is readable from the
code — but why it says it, and what it was chosen over. If a decision document is
edited in place when the decision changes, that history is destroyed: the reasoning that
produced the old rule disappears, and the new rule appears to have been obvious all
along. The next person re-derives the abandoned option from scratch.

## Decision

**Decisions are recorded as ADRs in `docs/adr/`, one file per decision, named
`ADR-NNN-kebab-slug.md`, and ADRs are immutable once written.** The registry's own
decisions are numbered in a separate series under `docs/adr/registry/`, so they do not
collide with the app's.

When a decision changes, write a **new** ADR that supersedes the old one, and say so in
both directions. The superseded ADR keeps its text and gets its status updated to point
at its replacement. Nothing else about it is edited. Typo fixes are the only exception.

## Consequences

- The ADR folder grows and never shrinks, and some of what it holds is wrong-on-purpose
  history. That is the archive doing its job.
- Reading the current rules means reading the latest ADR on a topic, not the lowest
  number. Status lines carry that weight, so they have to be accurate.
- A decision that is not written down is not a decision. Arguments settled in chat get
  an ADR or get re-argued.
