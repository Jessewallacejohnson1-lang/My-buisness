# Parked — out of scope for the registry

**Date:** 2026-09-22

The registry answers *where does Block Party look, and how*. It stops at raw fetched
content. Turning that content into events and postings is a separate problem, and the
decisions below are **not made yet**.

They are listed here so nobody improvises one mid-task and so nobody re-discovers them
as gaps. If one of these is needed, it gets grilled out and written as an ADR first.

| Parked | What is undecided |
| --- | --- |
| ~~**Staging table**~~ | Decided 2026-10-06 in [ADR-021](ADR-021-found-events-are-events.md): reviewed first in the app, then automatic below 1 wrong in 20. |
| ~~**Event dedupe**~~ | Decided 2026-10-06 in [ADR-021](ADR-021-found-events-are-events.md): merge only when certain; every source kept as a mention. |
| ~~**Recurring events**~~ | Decided 2026-10-06 in [ADR-021](ADR-021-found-events-are-events.md): a series with occurrences; one date cancels alone. |

None of these change anything in `sources/`. The registry format is additive (ADR-007),
so whatever is decided can be recorded without a rewrite.
