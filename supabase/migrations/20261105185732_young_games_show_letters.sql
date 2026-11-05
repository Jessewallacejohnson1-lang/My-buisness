-- A game at middle school level or younger doesn't wait for a logo: its team shows its first letter until one is found
-- (Jesse, 2026-11-05: "if there can not be a found logo letters are fine that should only be for middle school or younger").
-- High school and up still waits, hidden. The level is on the end of a game's sport ("Girls Basketball · 7th Grade",
-- read_events.bound_items), or starts it ("MS Coed Wrestling"). 20261105152417_every_game_white.sql's function but for that.
create or replace function private.game_waits_for_logos() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.status in ('approved', 'waiting_logo') then
    new.status := case when new.sport is not null and cardinality(new.team_ids) = 2
        and new.sport !~* '^ms |·\s*(ms|middle school|junior high|elementary|youth|[1-8](st|nd|rd|th)( grade)?)$'
        and exists (select 1 from unnest(new.team_ids) as k(id) left join public.teams t on t.id = k.id where t.logo_url is null)
      then 'waiting_logo' else 'approved' end;
  end if;
  return new;
end
$$;
