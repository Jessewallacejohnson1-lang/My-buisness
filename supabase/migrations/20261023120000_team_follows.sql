-- Follow a local team (BP app docs/plans/hello-drop, ticket 03; Jesse, 2026-10-23: "tap profile
-- picture and able to follow from there", "only have profiles for local teams", "go off logo
-- colors. add a database set with teams logos and up to 3 colors").
--
-- A team gets a uuid (town_follows keys every target by uuid; teams.id stays the readers' slug),
-- up to three colours read from its logo (references/team-follow/team_colors.py, most used
-- first) and `local`: the teams around St. Joseph, the only ones with a page and a Follow.
-- `team_page` is that page; `my_team_finals` is the hello pill's "Johnnies beat Gustavus 33–23".
-- The game card's JSON names each team's uuid, `local` and colours in 20261023120100_team_game.sql.

alter table public.teams
  add column if not exists uuid uuid not null default gen_random_uuid(),
  add column if not exists colors text[],
  add column if not exists local boolean not null default false;
alter table public.teams drop constraint if exists teams_uuid_key;
alter table public.teams add constraint teams_uuid_key unique (uuid);
alter table public.teams drop constraint if exists teams_colors_check;
alter table public.teams add constraint teams_colors_check
  check (colors is null or (cardinality(colors) between 1 and 3
                            and array_to_string(colors, ',') ~ '^#[0-9A-F]{6}(,#[0-9A-F]{6})*$'));

update public.teams set local = true
where id in ('saint-johns', 'saint-benedict', 'apollo', 'tech', 'cathedral', 'apollo-cathedral',
             'rocori', 'sartell', 'sauk-rapids-rice');

update public.teams set colors = array['#370657', '#020103', '#2E2E2E'] where id = 'albany';
update public.teams set colors = array['#DC1932', '#FECD33', '#221E20'] where id = 'alexandria';
update public.teams set colors = array['#0061A9', '#EF3B42', '#BABCC0'] where id = 'apollo-cathedral';
update public.teams set colors = array['#0061A9', '#EF3B42', '#BABCC0'] where id = 'apollo';
update public.teams set colors = array['#74243D', '#A9AAAB'] where id = 'augsburg';
update public.teams set colors = array['#32469D', '#CDCDCC', '#2F2F2F'] where id = 'bemidji';
update public.teams set colors = array['#003D7C', '#FED34F', '#F0B311'] where id = 'carleton';
update public.teams set colors = array['#FEE291', '#01447E'] where id = 'cathedral';
update public.teams set colors = array['#09194D', '#0C0B0C', '#6C6D6E'] where id = 'eden-valley-watkins';
update public.teams set colors = array['#005CB7', '#010202'] where id = 'foley';
update public.teams set colors = array['#221E20', '#FDCE07'] where id = 'gustavus-adolphus';
update public.teams set colors = array['#898C8D', '#231E20', '#E1DDDC'] where id = 'hamline';
update public.teams set colors = array['#52247E', '#221F1F', '#BCBDC0'] where id = 'little-falls';
update public.teams set colors = array['#E44924', '#315371', '#AF4734'] where id = 'macalester';
update public.teams set colors = array['#004A98', '#00833E', '#8B9091'] where id = 'minnewaska';
update public.teams set colors = array['#015543', '#FDCA2D'] where id = 'north-dakota-state';
update public.teams set colors = array['#DA230A', '#0F0C08', '#ADACAC'] where id = 'rocori';
update public.teams set colors = array['#BB2037', '#0F9CD7'] where id = 'saint-benedict';
update public.teams set colors = array['#BC0E33', '#02A2E2'] where id = 'saint-johns';
update public.teams set colors = array['#1A4EA2'] where id = 'sartell';
update public.teams set colors = array['#6A110E', '#0C0101'] where id = 'sauk-centre';
update public.teams set colors = array['#135432', '#FDCD30', '#A8AFB0'] where id = 'sauk-rapids-rice';
update public.teams set colors = array['#A10209', '#010101'] where id = 'st-cloud-state';
update public.teams set colors = array['#002E5A'] where id = 'st-peter';
update public.teams set colors = array['#010100', '#DB6A26'] where id = 'tech';
update public.teams set colors = array['#111112', '#F8C702', '#542074'] where id = 'waconia';
update public.teams set colors = array['#010101', '#C6C6C8', '#E11E28'] where id = 'willmar';

alter table public.town_follows drop constraint if exists town_follows_target_type_check;
alter table public.town_follows add constraint town_follows_target_type_check
  check (target_type in ('club', 'profile', 'place', 'team'));

create or replace function private.followable(p_type text, p_id uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select case p_type
    when 'profile' then private.findable(p_id)
    when 'place' then exists (select 1 from public.places pl where pl.id = p_id)
    when 'team' then exists (select 1 from public.teams t where t.uuid = p_id and t.local)
    else false
  end
$$;

-- 20261022170000_follow_places_and_people.sql's my_follows, with the teams you follow (their logo).
create or replace function public.my_follows()
returns table (target_type text, target_id uuid, name text, kind text, picture text, picture_kind text)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  me uuid := private.need_real();
begin
  return query
    select x.* from (
      select 'profile'::text, t.target_id, p.display_name, null::text, p.avatar_url, 'photo'::text
      from public.town_follows t
      join public.town_profiles p on p.user_id = t.target_id
      where t.follower_id = me and t.target_type = 'profile' and private.findable(t.target_id)
      union all
      select 'place'::text, t.target_id, pl.name, pl.primary_type, pic ->> 'url', pic ->> 'kind'
      from public.town_follows t
      join public.places pl on pl.id = t.target_id
      cross join lateral (select public.place_picture(pl.entry_id) as pic) pp
      where t.follower_id = me and t.target_type = 'place'
      union all
      select 'team'::text, t.target_id, tm.short_name, 'team'::text, tm.logo_url, 'logo'::text
      from public.town_follows t
      join public.teams tm on tm.uuid = t.target_id
      where t.follower_id = me and t.target_type = 'team'
    ) x (target_type, target_id, name, kind, picture, picture_kind)
    order by lower(x.name), x.target_id;
end;
$$;

-- A local team's page: who it is and its next games (today on, up to five), each with the
-- other team. Null for a team that isn't local.
create or replace function public.team_page(p_team uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', t.uuid, 'name', t.name, 'short', t.short_name, 'logo', t.logo_url, 'colors', t.colors,
    'games', coalesce((
      select jsonb_agg(g order by g ->> 'date', g ->> 'time')
      from (
        select jsonb_build_object('id', e.id, 'sport', e.sport, 'date', e.event_date,
                                  'time', e.start_time, 'location', e.location,
                                  'other', coalesce(o.short_name, o.name,
                                                    e.team_ids[case when e.team_ids[1] = t.id then 2 else 1 end])) as g
        from public.club_events e
        left join public.teams o on o.id = e.team_ids[case when e.team_ids[1] = t.id then 2 else 1 end]
        where t.id = any(e.team_ids) and e.status = 'approved' and e.cancelled_at is null
          and e.event_date >= (now() at time zone 'America/Chicago')::date
        order by e.event_date, e.start_time
        limit 5
      ) x), '[]'::jsonb))
  from public.teams t
  where t.uuid = p_team and t.local
$$;

-- The finals of games your followed teams played, read since `p_since`: the hello pill's "your
-- team's final". `mine` is the followed team's side, 0 or 1, in `game.teams` order.
create or replace function public.my_team_finals(p_since timestamptz)
returns table (event_id uuid, game jsonb, mine int, read_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select e.id,
         private.event_game(e.sport, e.team_ids, e.occasion) || jsonb_build_object('final', e.final_score),
         case when e.team_ids[1] = t.id then 0 else 1 end,
         e.final_checked_at
  from public.town_follows f
  join public.teams t on t.uuid = f.target_id
  join public.club_events e on t.id = any(e.team_ids)
  where f.follower_id = auth.uid() and f.target_type = 'team'
    and e.final_score is not null and e.cancelled_at is null
    and e.final_checked_at > p_since
  order by e.final_checked_at desc
$$;

revoke execute on function public.team_page(uuid) from public;
grant execute on function public.team_page(uuid) to anon, authenticated;
revoke execute on function public.my_team_finals(timestamptz) from public;
grant execute on function public.my_team_finals(timestamptz) to authenticated;
