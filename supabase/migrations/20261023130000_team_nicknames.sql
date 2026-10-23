-- What neighbours call a team (Jesse, 2026-10-23: "use nicknames if available"): the hello pill
-- says "Johnnies beat Gusties 33–23". Filled for the local teams; any other keeps its short name.

alter table public.teams add column if not exists nickname text;

update public.teams set nickname = n.nickname
from (values ('saint-johns', 'Johnnies'), ('saint-benedict', 'Bennies'), ('apollo', 'Eagles'),
             ('tech', 'Tigers'), ('cathedral', 'Crusaders'), ('rocori', 'Spartans'),
             ('sartell', 'Sabres'), ('sauk-rapids-rice', 'Storm'), ('gustavus-adolphus', 'Gusties'))
     as n(id, nickname)
where teams.id = n.id;

-- 20261023120100_team_game.sql's event_game, with the nickname.
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
                                                  'colors', t.colors, 'nickname', t.nickname) order by k.n)
              from unnest(p_team_ids) with ordinality as k(id, n)
              left join public.teams t on t.id = k.id))
  end
$$;
