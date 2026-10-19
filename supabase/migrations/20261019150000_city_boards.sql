-- A City's boards and commissions (BP app docs/plans/follows, ticket 03), as Jesse approved them on
-- 2026-10-19 (follows/assets/03-boards.md). Neighbours follow a board to get its meetings (follows
-- 04, town-feed 27). A City meeting is a draw 1 Event from the City's calendar; it belongs to the
-- board whose name its title starts with, so "City Council Work Session" is the City Council's.
-- A meeting matching no board belongs to the City only. Everyone may read the list.

create table if not exists public.city_boards (
  id             uuid primary key default gen_random_uuid(),
  town           text not null,              -- sources.town
  city_name      text not null,              -- the City's club_events.source_name: its parent
  name           text not null,              -- as the City writes it
  title_prefixes text[] not null,            -- a meeting title starting with one is this board's
  unique (town, name)
);

alter table public.city_boards enable row level security;
drop policy if exists "read city boards" on public.city_boards;
create policy "read city boards" on public.city_boards for select to anon, authenticated using (true);
grant select on public.city_boards to anon, authenticated;

-- The board a City meeting belongs to, or null.
create or replace function public.meeting_board(e public.club_events) returns uuid
language sql stable set search_path = public as $$
  select b.id from public.city_boards b
  where e.draw = 1 and e.source_name = b.city_name
    and exists (select 1 from unnest(b.title_prefixes) p where e.title ilike p || '%')
  order by b.name
  limit 1
$$;
grant execute on function public.meeting_board(public.club_events) to anon, authenticated;

insert into public.city_boards (town, city_name, name, title_prefixes) values
  ('st-joseph-mn', 'City of St. Joseph', 'City Council',                   array['City Council']),
  ('st-joseph-mn', 'City of St. Joseph', 'Planning Commission',            array['Planning Commission']),
  ('st-joseph-mn', 'City of St. Joseph', 'Park Board',                     array['Park Board']),
  ('st-joseph-mn', 'City of St. Joseph', 'Economic Development Authority', array['Economic Development Authority', 'EDA']),
  ('st-joseph-mn', 'City of St. Joseph', 'Joint Planning Board',           array['Joint Planning Board'])
on conflict (town, name) do update set city_name = excluded.city_name, title_prefixes = excluded.title_prefixes;
