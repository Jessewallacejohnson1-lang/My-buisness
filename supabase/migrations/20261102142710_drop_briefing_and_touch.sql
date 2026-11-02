-- The old Today briefing and its daily touch card (poll, history, trivia), dropped with Jesse's yes
-- (2026-11-02, the whole-app tidy). The app stopped reading them on 2026-10-25 (BP app
-- codebase-health 09) and their hourly job was unscheduled on 2026-10-30 (20261030202348). No
-- other function, view or app reads them. Their rows were saved before the drop, off git, in
-- ~/Documents/backups/2026-11-02-briefing-and-touch-tables.json.

-- Their triggers go with the tables.
drop table public.touch_votes;
drop table public.daily_touches;
drop table public.briefing_featured;
drop table public.daily_briefings;

drop function public.briefings_pending(date, integer);
drop function public.claim_trivia(date);
drop function public.claim_trivia_for_published_briefing();
drop function public.compose_briefing(date, jsonb, text, text, text);
drop function public.get_today_briefing(date, text);
drop function public.pick_trivia(date);
drop function public.publish_briefing(date);
drop function public.run_briefing_reconcile();
drop function public.trivia_streak(text);
drop function public.validate_touch_vote();
drop function public.pick_touch(date);
drop function public.claim_touch(date);
drop function public.touch_tally(uuid);
drop function public.touch_stats(uuid);
