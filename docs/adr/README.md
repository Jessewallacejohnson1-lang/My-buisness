# Architecture decision records

One file per decision, named `ADR-NNN-kebab-slug.md`, zero-padded to three digits and
numbered in the order written. ADRs are immutable: when a decision changes, a new ADR
supersedes the old one and the old one is never edited.

**Source-registry ADRs live in [`registry/`](registry/) and carry their own numbering**
(`ADR-001`–`ADR-009`), separate from the app ADRs in this folder. They cover the
`sources/` registry — what it holds, who may edit it, and how runs behave. `registry/PARKED.md`
lists what the registry deliberately does not decide.
