-- The game card's JSON names each team's uuid, whether it's local and its logo's colours
-- (hello-drop 03; the columns are 20261023120000_team_follows.sql's), so the card opens a local
-- team's page. On its own so the Town feed's stories load it without the follows.

-- 20261020120100_game_card_feed.sql's event_game, with each team's uuid, whether it's local, and
-- its logo's colours, so the card can open a local team's page.
create or replace function private.event_game(p_sport text, p_team_ids text[], p_occasion text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case when cardinality(p_team_ids) = 2 and p_sport is not null then jsonb_build_object(
    'sport', p_sport,
    'occasion', p_occasion,
    'teams', (select jsonb_agg(jsonb_build_object('name', coalesce(t.name, k.id),
                                                  'short', coalesce(t.short_name, t.name, k.id),
                                                  'logo', t.logo_url, 'color', t.color,
                                                  'id', t.uuid, 'local', coalesce(t.local, false),
                                                  'colors', t.colors) order by k.n)
              from unnest(p_team_ids) with ordinality as k(id, n)
              left join public.teams t on t.id = k.id))
  end
$$;
