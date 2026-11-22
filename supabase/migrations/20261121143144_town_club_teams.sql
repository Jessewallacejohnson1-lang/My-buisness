-- Town and junior teams on a sport's page (BP app school-search 12; Jesse, 2026-11-21: "I agree with all your picks",
-- then at Check-in 1 "put all the teams in alphabetical order" and "use their logos if they have any").
-- Seven local teams, each with its own page (`local`) and one sport: the five town baseball teams and the two junior
-- hockey teams. `town` marks a town team: the town under its disc on a sport's page, and what keeps it off the
-- Schools row and onboarding's school tiles. Their games come from the morning readers (read_events.py:
-- hometeamsonline, igniter, tix). Each logo went live on two separate checks agreeing
-- (BP app references/town-club-teams/logos/checks.md).
-- The most frequent opponents get their rows and logos now too, with no page (`local` false), so their games show
-- (a game shows only once both teams have a logo, MEMORY.md 2026-11-05).

alter table public.teams add column if not exists town text;
comment on column public.teams.town is
  'A town or junior team''s town (St. Joseph for the Joes, BP app school-search 12); null for a school.';

-- A new team's name, short name or alias must be no other team's: write_judged.known_teams gives a name to whichever
-- row claims it first, so a clash would hand one team's games to another.
do $$
declare clash text;
begin
  with slug(k, id) as (
    select trim(both '-' from regexp_replace(lower(replace(n, '''', '')), '[^a-z0-9]+', '-', 'g')), t.id
    from public.teams t, unnest(array[t.id, t.name, t.short_name] || t.aliases) n
    where n is not null),
  new(n) as (values ('St. Joseph Joes'), ('Joes'), ('St Joseph Joes'), ('Saint Joseph Joes'), ('Sartell Muskies'), ('Muskies'), ('Sartell Stone Poneys'), ('Stone Poneys'), ('Sauk Rapids Cyclones'), ('Cyclones'), ('Cold Spring Springers'), ('Springers'), ('St. Cloud Norsemen'), ('Norsemen'), ('St Cloud Norsemen'), ('Granite City Lumberjacks'), ('Lumberjacks'), ('Albertville Anglers'), ('Clearwater River Cats'), ('River Cats'), ('Aberdeen Wings'), ('Austin Bruins'), ('Bismarck Bobcats'), ('Minot Minotauros'), ('Watertown Shamrocks'), ('Alexandria Blizzard'), ('MN Vulcans'), ('MN Wilderness'), ('North Iowa Bulls'), ('Willmar WarHawks'))
  select string_agg(distinct new.n || ' (' || slug.id || ')', ', ') into clash
  from new join slug on slug.k = trim(both '-' from regexp_replace(lower(replace(new.n, '''', '')), '[^a-z0-9]+', '-', 'g'))
  where slug.id not in ('st-joseph-joes', 'sartell-muskies', 'sartell-stone-poneys', 'sauk-rapids-cyclones', 'cold-spring-springers', 'st-cloud-norsemen', 'granite-city-lumberjacks', 'albertville-anglers', 'clearwater-river-cats', 'aberdeen-wings', 'austin-bruins', 'bismarck-bobcats', 'minot-minotauros', 'watertown-shamrocks', 'alexandria-blizzard', 'mn-vulcans', 'mn-wilderness', 'north-iowa-bulls', 'willmar-warhawks');
  if clash is not null then
    raise exception 'a new team''s name is already another team''s: %', clash;
  end if;
end $$;

insert into public.teams (id, name, short_name, local, town, aliases, logo_url, color, colors) values
  -- The seven with a page: the colours their pages wear, read off their logos (picked).
  ('st-joseph-joes', 'St. Joseph Joes', 'Joes', true, 'St. Joseph', array['St Joseph Joes', 'Saint Joseph Joes'], 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/teams/st-joseph-joes/logo-c35c4c888d.png', '#1C2F63', array['#1C2F63', '#C8332B']),
  ('sartell-muskies', 'Sartell Muskies', 'Muskies', true, 'Sartell', '{}'::text[], 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/teams/sartell-muskies/logo-d5cee89c01.png', '#00634A', array['#00634A', '#292752']),
  ('sartell-stone-poneys', 'Sartell Stone Poneys', 'Stone Poneys', true, 'Sartell', '{}'::text[], 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/teams/sartell-stone-poneys/logo-116bc4f534.png', '#0B2B92', array['#0B2B92', '#6CADD4']),
  ('sauk-rapids-cyclones', 'Sauk Rapids Cyclones', 'Cyclones', true, 'Sauk Rapids', '{}'::text[], 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/teams/sauk-rapids-cyclones/logo-9fa10746bd.png', '#A80D0D', array['#A80D0D', '#0B0A0A']),
  ('cold-spring-springers', 'Cold Spring Springers', 'Springers', true, 'Cold Spring', '{}'::text[], 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/teams/cold-spring-springers/logo-c2e30140c3.png', '#C42233', array['#C42233']),
  ('st-cloud-norsemen', 'St. Cloud Norsemen', 'Norsemen', true, 'St. Cloud', array['St Cloud Norsemen'], 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/teams/st-cloud-norsemen/logo-3f36208681.png', '#2E3060', array['#2E3060', '#8D8E90']),
  ('granite-city-lumberjacks', 'Granite City Lumberjacks', 'Lumberjacks', true, 'Sauk Rapids', '{}'::text[], 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/teams/granite-city-lumberjacks/logo-e319fa26c4.png', '#112D70', array['#112D70', '#D81818']),
  -- Their most frequent opponents: no page; a game's card shows their logo (colours read as the morning reads them).
  ('albertville-anglers', 'Albertville Anglers', 'Albertville Anglers', false, null, '{}'::text[], 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/teams/albertville-anglers/logo-c0955555c3.png', '#080808', array['#080808', '#2B2C2B']),
  ('clearwater-river-cats', 'Clearwater River Cats', 'River Cats', false, null, '{}'::text[], 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/teams/clearwater-river-cats/logo-24e91acb04.png', '#323132', array['#323132', '#4E4D4E', '#8B8B8B']),
  ('aberdeen-wings', 'Aberdeen Wings', 'Aberdeen Wings', false, null, '{}'::text[], 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/teams/aberdeen-wings/logo-df5b55f746.png', '#050505', array['#050505', '#D0D1D2', '#B0B0B1']),
  ('austin-bruins', 'Austin Bruins', 'Austin Bruins', false, null, '{}'::text[], 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/teams/austin-bruins/logo-85df444726.png', '#0B0A0E', array['#0B0A0E', '#2E2D2F', '#F7BB46']),
  ('bismarck-bobcats', 'Bismarck Bobcats', 'Bismarck Bobcats', false, null, '{}'::text[], 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/teams/bismarck-bobcats/logo-f20c5eb30d.png', '#090909', array['#090909', '#2E2D2D', '#71706B']),
  ('minot-minotauros', 'Minot Minotauros', 'Minot Minotauros', false, null, '{}'::text[], 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/teams/minot-minotauros/logo-c7120d4ce0.png', '#070505', array['#070505', '#B1AA93', '#510814']),
  ('watertown-shamrocks', 'Watertown Shamrocks', 'Watertown Shamrocks', false, null, '{}'::text[], 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/teams/watertown-shamrocks/logo-a99a922360.png', '#0E6E39', array['#0E6E39', '#033014', '#CFCFCF']),
  ('alexandria-blizzard', 'Alexandria Blizzard', 'Alexandria Blizzard', false, null, '{}'::text[], 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/teams/alexandria-blizzard/logo-95763fb49b.png', '#050505', array['#050505', '#CFD0D0', '#707070']),
  ('mn-vulcans', 'MN Vulcans', 'MN Vulcans', false, null, '{}'::text[], 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/teams/mn-vulcans/logo-3de98825a9.png', '#0A0B0B', array['#0A0B0B', '#2D2D2D', '#4E4E4D']),
  ('mn-wilderness', 'MN Wilderness', 'MN Wilderness', false, null, '{}'::text[], 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/teams/mn-wilderness/logo-257f1dec45.png', '#070707', array['#070707', '#4D4E4E', '#2E2E2E']),
  ('north-iowa-bulls', 'North Iowa Bulls', 'North Iowa Bulls', false, null, '{}'::text[], 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/teams/north-iowa-bulls/logo-282e09d453.png', '#10334C', array['#10334C', '#AEAFAF', '#CFD0CF']),
  ('willmar-warhawks', 'Willmar WarHawks', 'Willmar WarHawks', false, null, '{}'::text[], 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/teams/willmar-warhawks/logo-e73bffa1fc.png', '#070707', array['#070707', '#2E2F2F', '#8F9090'])
on conflict (id) do update set name = excluded.name, short_name = excluded.short_name, local = excluded.local,
  town = excluded.town, aliases = excluded.aliases, logo_url = excluded.logo_url, color = excluded.color,
  colors = excluded.colors;

insert into public.team_activities (team_id, name, kind, sort) values
  ('st-joseph-joes', 'Baseball', 'sport', 0),
  ('sartell-muskies', 'Baseball', 'sport', 0),
  ('sartell-stone-poneys', 'Baseball', 'sport', 0),
  ('sauk-rapids-cyclones', 'Baseball', 'sport', 0),
  ('cold-spring-springers', 'Baseball', 'sport', 0),
  ('st-cloud-norsemen', 'Hockey', 'sport', 0),
  ('granite-city-lumberjacks', 'Hockey', 'sport', 0)
on conflict (team_id, name) do nothing;
