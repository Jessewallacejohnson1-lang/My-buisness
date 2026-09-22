# Parked — out of scope for the registry

**Date:** 2026-09-22

The registry answers *where does Block Party look, and how*. It stops at raw fetched
content. Turning that content into events and postings is a separate problem, and the
decisions below are **not made yet**.

They are listed here so nobody improvises one mid-task and so nobody re-discovers them
as gaps. If one of these is needed, it gets grilled out and written as an ADR first.

| Parked | What is undecided |
| --- | --- |
| **Staging table** | Whether fetched content lands in a staging table for review before it becomes an event, and who or what approves it. |
| **Event dedupe** | How the same event mentioned by several sources — or by one source several times — collapses into one posting. Ties directly into the trust tiers in ADR-001. |
| **Recurring events** | How "every Friday, May through October" is represented, expanded, and cancelled for a single week. |

None of these change anything in `sources/`. The registry format is additive (ADR-007),
so whatever is decided can be recorded without a rewrite.
