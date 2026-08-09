# Today briefing — pre-flight

Before archiving `feat/today-briefing` to TestFlight.

Everything below the "must check on a real device" line is genuinely unverified.
The simulator setup here has **no scroll or gesture automation**, so a scroll
regression passes every headless screenshot check — CLAUDE.md says so explicitly,
and it has shipped that way before.

---

## Must check on a real device

1. **Scrolling.** Open Today and drag from the MIDDLE of the poll card, not the
   header. If the screen only scrolls over the almanac, a pan-competing gesture
   got attached to a scrollable cell and the briefing is broken. The poll rows use
   `ButtonStyle.isPressed` and should be fine — this is the check that proves it.
2. **Vote once.** Tap an option. The bar should sweep left→right over ~0.3s with
   the percentage counting up beside it, one light tap on press and one success
   tap as it settles. Then confirm it landed:
   ```sql
   select * from touch_votes order by created_at desc limit 5;
   ```
3. **Vote twice.** Tapping again must do nothing. A vote is final in v1.
4. **RSVP.** The plus should rotate into a check with the ring burst. Confirm the
   going count moves with it and does not disagree with the button.
5. **Reach the bottom.** The checkmark draws over 0.4s with one success haptic,
   the FIRST time that day. Scroll away and back — it must stay quiet.
6. **Pull to refresh.** With today's briefing already loaded it should bounce and
   settle with no spinner and no network call.
7. **Airplane mode.** Force-quit, enable airplane mode, reopen. The full briefing
   must render from cache. This is the morning bad-wifi case and it is the single
   most valuable thing on this list.
8. **Reduce Motion** (Settings → Accessibility → Motion). Everything must still be
   fully visible: no sweep, no draw-on, no missing content.
9. **Dynamic Type at accessibility sizes.** Check the poll options (longest is 35
   characters) and the spotlight blurb (up to 27 words) do not clip.

## Instruments, if you have time

Your Phase 4 gate asks for 120 fps with no dropped frames on module entrance.
Untested. Run the Animation Hitches template while scrolling Today top to bottom.

---

## Before you archive

- Bump the build number.
- Verify the **Release** configuration builds clean — everything so far has been
  Debug. The DEBUG-only preview gates (`-briefing-preview`, `-briefing-gallery`,
  `BriefingSample`) compile out, but confirm rather than assume.
- Confirm `BlockParty/Config/MapboxConfig.swift` and `GooglePlacesConfig.swift`
  exist in whichever checkout you archive from. They are gitignored, and a fresh
  worktree will not have them.
- The bundle id is `Jesse.BlockParty`. Before archiving, verify the new App Store
  Connect record exists and the Google Places key allows this bundle id; otherwise
  the build can install while every venue photo remains blank.

## Tester notes — suggested

> Today is now a daily briefing rather than a feed. It ends: when you reach the
> bottom, you're caught up until 6 AM. There's one question a day — answer it,
> results show straight away.
>
> New in this build: the briefing loads in one request and is saved to your phone,
> so it opens instantly and still works with no signal.
>
> Block Party tailors itself to you. Your daily line is written from your own
> RSVPs and the last week you've had, and what gets recommended — places, events —
> follows what you've saved, joined and shown interest in. This build also records
> which parts of the briefing get used, so we can tell what's worth keeping.
>
> All of it stays with us: our own database, no third-party analytics, nothing sold
> or shared, and nobody can see anyone else's activity.

Say it plainly rather than implying the app collects nothing — personalization IS
the product here, and understating it reads worse than owning it. `Log.swift`
carries the full inventory of what is used and why; a privacy policy saying the
same thing is the real fix before public release.

---

## Rollback

The briefing is additive at the database level — no existing table changed shape,
so rolling back the app is safe and leaves no orphaned state.

To take Today back to the feed, revert the app commits; the migrations can stay.
The feed views were deliberately NOT deleted:

```
git revert --no-commit d836b8d^..HEAD   # app changes only
```

`TodayFeedView` and its card stack are still in `Features/Home/Feed/` and still
compile.
