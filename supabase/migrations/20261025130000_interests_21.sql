-- The interests go from 18 to 21 (BP app docs/plans/onboarding, tickets 15 and 20). Every old id
-- stored on the server moves onto the new ones, the same map as `Interests.legacy` in the app:
-- a profile keeps both halves of a pick that split (Art & exhibits is Art & theater and Crafts &
-- making), an Event keeps the first until ticket 21 re-tags it. Library & books keeps its id, so
-- it can't also bring Talks & lectures: every save would add Talks back. Triggers keep doing it for older
-- app builds and for the morning job's last run on the old list. Safe to run twice.

create or replace function private.interests_21(ids text[], events boolean default false)
returns text[]
language sql
immutable
set search_path = ''
as $$
  select case when ids is null then null else coalesce((
    select array_agg(id order by first_at)
    from (
      select m.id, min(o.ord * 10 + m.sub) as first_at
      from unnest(ids) with ordinality as o(old, ord)
      cross join lateral unnest(case o.old
        when 'trails_hiking'   then array['outdoors']
        when 'parks_gardens'   then array['outdoors']
        when 'lakes_swimming'  then array['lakes_biking']
        when 'biking'          then array['lakes_biking']
        when 'farmers_market'  then array['markets']
        when 'breweries'       then array['bars']
        when 'fitness_yoga'    then array['health']
        when 'health_wellness' then array['health']
        when 'art_exhibits'    then case when events then array['art_theater'] else array['art_theater', 'crafts'] end
        when 'sports_leagues'  then case when events then array['watch_sports'] else array['watch_sports', 'play_sports'] end
        else array[o.old]
      end) with ordinality as m(id, sub)
      group by m.id
    ) mapped
  ), '{}'::text[]) end
$$;

create or replace function private.interests_21_row()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.interests := private.interests_21(new.interests, tg_table_name <> 'town_profiles');
  -- Nested, not `and`: PL/pgSQL reads new.category even when the first half is false, and only
  -- club_events has one.
  if tg_table_name = 'club_events' then
    if new.category is not null then
      new.category := (private.interests_21(array[new.category], true))[1];
    end if;
  end if;
  return new;
end
$$;

drop trigger if exists interests_21 on public.town_profiles;
create trigger interests_21 before insert or update of interests on public.town_profiles
  for each row execute function private.interests_21_row();
drop trigger if exists interests_21 on public.club_events;
create trigger interests_21 before insert or update of interests, category on public.club_events
  for each row execute function private.interests_21_row();
drop trigger if exists interests_21 on public.board_items;
create trigger interests_21 before insert or update of interests on public.board_items
  for each row execute function private.interests_21_row();

-- The map, checked before anything moves.
do $$
begin
  assert private.interests_21(array['books', 'art_exhibits', 'coffee']) = array['books', 'art_theater', 'crafts', 'coffee'];
  assert private.interests_21(array['trails_hiking', 'parks_gardens', 'faith']) = array['outdoors', 'faith'];
  assert private.interests_21(array['sports_leagues', 'books'], true) = array['watch_sports', 'books'];
  assert private.interests_21(array['outdoors', 'campus']) = array['outdoors', 'campus'];
  assert private.interests_21('{}'::text[]) = '{}'::text[];
  assert private.interests_21(null) is null;
end
$$;

update public.town_profiles set interests = interests
  where interests && array['trails_hiking', 'parks_gardens', 'lakes_swimming', 'biking', 'farmers_market',
    'breweries', 'fitness_yoga', 'health_wellness', 'art_exhibits', 'sports_leagues'];
update public.club_events set interests = interests
  where interests && array['trails_hiking', 'parks_gardens', 'lakes_swimming', 'biking', 'farmers_market',
    'breweries', 'fitness_yoga', 'health_wellness', 'art_exhibits', 'sports_leagues']
     or category in ('trails_hiking', 'parks_gardens', 'lakes_swimming', 'biking', 'farmers_market',
    'breweries', 'fitness_yoga', 'health_wellness', 'art_exhibits', 'sports_leagues');
update public.board_items set interests = interests
  where interests && array['trails_hiking', 'parks_gardens', 'lakes_swimming', 'biking', 'farmers_market',
    'breweries', 'fitness_yoga', 'health_wellness', 'art_exhibits', 'sports_leagues'];
