-- The photo judge (BP app docs/plans/event-photos/issues/30-photo-judge-agent.md; Jesse, 2026-11-22: "the goal is for
-- people scrolling to feel interested from the photo and has to relate to event or post").
--
-- 1. place_photos.judged and judged_why: a second look's verdict on a picture the morning's photo step or the dig
--    picked (sources/models/photo-judge.md): run, weak or down. Null is a picture no judge has seen.
-- 2. public.judge_photos: the morning's judge-keep (sources/scripts/event_photos.py) saves a verdict on a picture's
--    rows; down retires them, so each card falls back to its place's own picture. Only those two steps' own picks:
--    the Watch key still may not take a person's photo down (watch_saves.test.mjs).
--
-- Roll back: drop function public.judge_photos(bigint[], text, text); alter table public.place_photos drop column
-- judged, drop column judged_why.

-- 1.
alter table public.place_photos
  add column judged text check (judged in ('run', 'weak', 'down')),
  add column judged_why text;
comment on column public.place_photos.judged is
  'The photo judge''s verdict on a pick of the morning''s photo step or the dig: run, weak or down (BP app event-photos 30). Null: not judged.';

-- 2.
create or replace function public.judge_photos(p_ids bigint[], p_verdict text, p_why text)
returns int
language sql
security definer
set search_path = ''
as $$
  with judged as (
    update public.place_photos
       set judged = p_verdict, judged_why = left(p_why, 200),
           status = case when p_verdict = 'down' then 'retired' else status end
     where id = any(p_ids) and proposed_by in ('event photos', 'the dig') and status = 'live'
    returning 1)
  select count(*)::int from judged;
$$;
revoke all on function public.judge_photos(bigint[], text, text) from public, anon, authenticated;
grant execute on function public.judge_photos(bigint[], text, text) to watch, service_role;
