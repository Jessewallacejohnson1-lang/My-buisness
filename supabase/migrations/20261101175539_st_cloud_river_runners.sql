-- St. Cloud River Runners, the running club nearest St. Joseph (Jesse, 2026-11-01: "i agree", to adding it;
-- no running club of St. Joseph's own turned up). Each fact is from the club's own pages, read 2026-11-01:
-- https://www.scrr.org/club-runs (a Sunday run at 7:30 AM from The Local Blend in St. Joseph; Saturday
-- breakfast runs from St. Cloud-area restaurants, the week's spot posted Thursdays in its Facebook group) and
-- https://www.scrr.org/membership-information (since 1980, every level welcome, no membership needed to run,
-- puts on the Lake Wobegon Trail Marathon). The marathon's St. Joseph finish is from its Wikipedia page. Only
-- the Sunday run is a meeting rule: the Saturday spot moves every week. The words are the agent's. A group
-- already there by name is left as it is, so this runs once.

insert into public.clubs (name, kind, schedule, location, description, page_url, entry_id, place_entry_id, meets, status)
select v.name, v.kind, v.schedule, v.location, v.description, v.page_url, v.entry_id, v.place_entry_id, v.meets, 'approved'
from (values
  ('St. Cloud River Runners', 'Running', 'Sundays at 7:30 AM', 'The Local Blend',
   $about$Central Minnesota's running club since 1980, for every pace from a first 5K to ultramarathons. On Sundays the club runs from The Local Blend in St. Joseph at 7:30 a.m. On Saturdays it meets at a different St. Cloud-area restaurant, runs, then stays for breakfast; the week's spot goes up in the club's Facebook group on Thursdays. You don't have to be a member to come along. The club also puts on the Lake Wobegon Trail Marathon each May, which finishes in St. Joseph.$about$,
   'https://www.scrr.org/club-runs', 'group-st-cloud-river-runners', 'local-blend',
   '[{"what": "Sunday run", "days": ["sun"], "weeks": null, "time": "07:30"}]'::jsonb)
) as v (name, kind, schedule, location, description, page_url, entry_id, place_entry_id, meets)
where not exists (select 1 from public.clubs c where c.name = v.name);
