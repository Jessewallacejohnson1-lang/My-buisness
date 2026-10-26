-- Every name a team goes by (Jesse, 2026-10-26). The morning writer looks a game's two names up in
-- each team's id, name, short name and aliases (write_judged.known_teams); a name no team goes by
-- gets a normal card and a "who is this" line, instead of a new team. Before this, each new
-- spelling made its own team: 11 cut-off copies ("Kennedy Community MS (Mid") in one morning.
-- A cut-off bracket at a name's end is ignored by the lookup, so it needs no alias.

alter table public.teams add column if not exists aliases text[] not null default '{}';

update public.teams t set aliases = a.names
from (values
  ('kennedy', array['Kennedy Community MS', 'Kennedy Community Middle School']),
  ('apollo', array['St. Cloud Apollo']),
  ('tech', array['St. Cloud Tech']),
  ('cathedral', array['St. Cloud Cathedral']),
  ('kimball', array['Kimball Area']),
  ('saint-johns', array['SJU', 'Saint John''s University', 'St. John''s']),
  ('saint-benedict', array['CSB', 'College of Saint Benedict', 'St. Ben''s']),
  ('st-johns-prep', array['Saint John''s Prep', 'Saint John''s Preparatory School']),
  ('minnesota-morris', array['UMN Morris']),
  ('msu-moorhead', array['Minnesota State Moorhead'])
) as a(id, names)
where t.id = a.id;
