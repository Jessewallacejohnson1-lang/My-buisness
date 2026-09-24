## Definition of done

A change is not done until all four are true. Say which ones you ran.

1. **It builds clean on the simulator** — no new warnings. `[prose]` The repo holds a
   0-warning bar; nothing enforces it but you.
2. **Tests pass** `[ci]` — `BlockPartyTests`, on a **non-primary** simulator `[hook]`, with
   a new test file **registered** `[test]` so it actually runs. That check is on
   registration, not a count — confirm by hand that the **executed count rose**. Commands:
   `docs/rules/build.md`.
3. **You screenshotted it** `[prose]` — launch on the sim with the right debug flag,
   capture, and show Jesse the actual screen. For a visual change, count pixels in the
   region you touched.
4. **The logs are updated** `[prose]` — if the work touched them:
   - map work → `MAP_BUILD_LOG.md` (chronological; the record of what is verified)
   - an identifier, a constant, or a deliberate exception → `DECISIONS.md`
   - anything deleted, parked, or recovered from the strip-down → `docs/GUTTING-LEDGER.md`
   - a correction from Jesse → `MEMORY.md`

**Not part of done: the end-of-production checks.** `[prose]` `docs/SHIP-CHECKLIST.md` holds
the checks that run once, before the App Store build, instead of on every change — the
Dynamic Type / text-size layout walk is the first of them (Jesse, 2026-09-22), and it skips
itself unless `TEST_RUNNER_BP_SHIP_AUDIT=1` is passed. **Do not re-verify anything listed
there as confirmed.** That file's *Confirmed* table names the date and the evidence;
re-running a confirmed check is the redundancy it exists to stop. Something that belongs at
the end of production goes into that file, not into this section.
