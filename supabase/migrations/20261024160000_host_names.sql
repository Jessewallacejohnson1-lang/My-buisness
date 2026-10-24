-- A Town card's host picture by the name the card shows (Jesse, 2026-10-24). The campus calendar
-- splits its Events among hosts by display name ("CSB SJU Campus Events", "CSB Athletics"), and a few
-- writers name a place differently from the registry ("Coborn's", "Flour & Flower Bakery"), so
-- sources.name never matched them and their cards kept a letter. host_entries names the registry
-- entry for such a host; it wins over sources.name, so JoeTown shows the City's logo, not its photo.
-- Read only through private.host_picture (security definer), so no read rule.

create table if not exists public.host_entries (
  name text primary key,
  entry_id text not null
);
alter table public.host_entries enable row level security;
revoke all on public.host_entries from anon, authenticated;

insert into public.host_entries (name, entry_id) values
  ('CSB SJU Campus Events', 'csbsju-events'),
  ('CSB SJU Libraries', 'csbsju-events'),
  ('CSB SJU', 'csbsju-events'),
  ('CSB SJU Outdoor U', 'csbsju-events'),
  ('CSB SJU Literary Arts Institute', 'csbsju-events'),
  ('Saint John''s School of Theology', 'csbsju-events'),
  ('CSB Athletics', 'activities-athletic-csb'),
  ('SJU Athletics', 'activities-athletic-sju'),
  ('Saint Benedict''s Monastery', 'benedict-of-of-order-sisters-st'),
  ('Coborn''s', 'coborns'),
  ('Flour & Flower Bakery', 'flour-and-flower'),
  ('JoeTown', 'city-of-st-joseph')
on conflict (name) do update set entry_id = excluded.entry_id;

create or replace function private.host_picture(p_source_name text, p_group_entry text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select private.entry_picture(coalesce(
    (select h.entry_id from public.host_entries h where h.name = p_source_name),
    (select s.entry_id from public.sources s where s.name = p_source_name order by s.entry_id limit 1),
    p_group_entry))
$$;
