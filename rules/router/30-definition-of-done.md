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
