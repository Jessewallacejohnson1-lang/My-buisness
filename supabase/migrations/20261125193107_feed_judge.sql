-- The feed judge (BP app docs/plans/watch-every-place/issues/52; Jesse, 2026-11-25: fixes may go live when both judges agree).
-- After each Apify check two judges read that check's new and changed Events and News beside their own posts
-- (sources/scripts/feed_judge.py, sources/models/feed-judge.md).
--
-- 1. public.feed_judgments: what they said of each item, one row a reading. `read_as` is the fingerprint of what they read,
--    so an unchanged item isn't judged again; `was` is what a fix or a take-out changed, to put it back by hand. The morning
--    report lists every row but the fine ones. No one in the app reads it.
-- 2. public.feed_judge(row): saves one, and does what both judges said; the answer is what it did. Only a found Event (never a neighbour's, a Group's
--    or a game) or a News the app shows. A correction is no move: no card says it moved, unless someone is Going or liked
--    it, who should hear its right day. An Event or News a neighbour is Going to or liked is never taken out: `left`.
--
-- Roll back: drop function public.feed_judge(jsonb); drop table public.feed_judgments;

-- 1.
create table public.feed_judgments (
  id        bigint generated always as identity primary key,
  event_id  uuid references public.club_events(id) on delete cascade,
  news_id   uuid references public.board_items(id) on delete cascade,
  title     text not null,
  read_as   text not null,
  outcome   text not null check (outcome in ('fine', 'fixed', 'taken out', 'left', 'differ', 'unsure')),
  why       text check (length(why) <= 600),
  was       jsonb,
  judged_at timestamptz not null default now(),
  constraint feed_judgments_one_item check (num_nonnulls(event_id, news_id) = 1)
);
create index feed_judgments_event on public.feed_judgments (event_id);
create index feed_judgments_news on public.feed_judgments (news_id);
create index feed_judgments_judged_at on public.feed_judgments (judged_at);
comment on table public.feed_judgments is
  'What the two feed judges said of each Event and News Apify brought (BP app watch-every-place 52). Only the checks use it.';
alter table public.feed_judgments enable row level security;
revoke all on public.feed_judgments from anon, authenticated;
grant select on public.feed_judgments to watch;
create policy "watch rows" on public.feed_judgments for select to watch using (true);

-- 2.
create or replace function public.feed_judge(p_row jsonb)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  r jsonb := p_row;
  fix jsonb := coalesce(p_row->'fix', '{}');
  e public.club_events;
  n public.board_items;
  followed boolean;
  done text := p_row->>'outcome';
  before jsonb;
begin
  if r ? 'event_id' then
    select * into e from public.club_events where id = (r->>'event_id')::uuid for update;
    if not found then return 'gone'; end if;
    followed := exists (select 1 from public.event_rsvps x where x.event_id = e.id)
             or exists (select 1 from public.event_likes x where x.event_id = e.id);
    if done in ('fixed', 'taken out') and (e.status <> 'approved' or e.kind is distinct from 'event' or e.submitted_by is not null
        or e.club_id is not null or e.sport is not null or e.cancelled_at is not null) then
      done := 'left';
    elsif done = 'taken out' and followed then
      done := 'left';
    elsif done = 'taken out' then
      before := jsonb_build_object('status', e.status);
      update public.club_events set status = 'rejected', review_reason = r->>'reason' where id = e.id;
    elsif done = 'fixed' then
      select jsonb_object_agg(k, to_jsonb(e)->k) into before
      from (select jsonb_object_keys(fix) union select 'moved_from' where fix ? 'moved_at') x(k) where to_jsonb(e) ? k;
      update public.club_events set
        title = coalesce(nullif(fix->>'title', ''), title),
        event_date = coalesce((fix->>'event_date')::date, event_date),
        start_time = case when fix ? 'start_time' then fix->>'start_time' else start_time end,
        all_day = case when fix ? 'start_time' then fix->>'start_time' is null else all_day end,
        end_at = case when fix ? 'end_at' then (fix->>'end_at')::timestamptz else end_at end,
        location = coalesce(nullif(fix->>'location', ''), location),
        place_entry_id = case when fix ? 'location' then fix->>'place_entry_id' else place_entry_id end,
        -- The next morning's map spots find the new place's.
        lat = case when fix ? 'location' then null else lat end,
        lng = case when fix ? 'location' then null else lng end,
        spot_looked_at = case when fix ? 'location' then null else spot_looked_at end,
        description = coalesce(nullif(fix->>'description', ''), description),
        about_written_at = case when fix ? 'description' then now() else about_written_at end,
        price = case when fix ? 'price' then nullif(fix->>'price', '') else price end,
        ages = case when fix ? 'ages' then nullif(fix->>'ages', '') else ages end
      where id = e.id;
      if not followed or fix ? 'moved_at' then
        update public.club_events set
          moved_at = case when fix ? 'moved_at' then null else e.moved_at end,
          moved_from = case when fix ? 'moved_at' then null else e.moved_from end
        where id = e.id;
      end if;
    end if;

  elsif r ? 'news_id' then
    select * into n from public.board_items where id = (r->>'news_id')::uuid for update;
    if not found then return 'gone'; end if;
    if done in ('fixed', 'taken out') and n.status <> 'published' then
      done := 'left';
    elsif done = 'taken out' and exists (select 1 from public.news_likes x where x.item_id = n.id) then
      done := 'left';
    elsif done = 'taken out' then
      before := jsonb_build_object('status', n.status);
      update public.board_items set status = 'archived' where id = n.id;
    elsif done = 'fixed' then
      select jsonb_object_agg(k, to_jsonb(n)->k) into before
      from jsonb_object_keys(fix) k where to_jsonb(n) ? k;
      update public.board_items set
        title = coalesce(nullif(fix->>'title', ''), title),
        blurb = coalesce(nullif(fix->>'blurb', ''), blurb),
        ends_on = case when fix ? 'ends_on' then (fix->>'ends_on')::date else ends_on end
      where id = n.id;
    end if;
  end if;

  insert into public.feed_judgments (event_id, news_id, title, read_as, outcome, why, was)
  values ((r->>'event_id')::uuid, (r->>'news_id')::uuid, r->>'title', r->>'read_as', done, left(r->>'why', 600), before);
  return done;
end;
$$;
revoke all on function public.feed_judge(jsonb) from public, anon, authenticated;
grant execute on function public.feed_judge(jsonb) to watch, service_role;

-- The first pass's corrected title ran past its card's 2 lines (headline_fits).
update public.board_items
set title = 'Weckström MIAC Defensive Player', blurb = 'Player of the Week: the freshman goalie stopped 54 of 55 shots.'
where id = 'd5b7b205-4548-46f7-aa18-2235f4c47948' and title = 'Weckström MIAC Defensive Player of Week';
