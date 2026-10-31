-- One feed action per person per Event per kind per Town day (BP app docs/plans/loopholes, ticket 04).
-- Any account could send views without end, and the 10-minute recount (private.feed_item_stats) reads
-- them all. A repeat is skipped quietly, so the app's batch of views and opens still lands whole and
-- the app doesn't change. Jesse's weekly views count each card once a day from here on.
--
-- Shares come back too: 20261026182034_report.sql remade the action check without 'share', so every
-- share the app sent since Oct 26 was refused.

alter table public.feed_actions drop constraint feed_actions_action_check;
alter table public.feed_actions add constraint feed_actions_action_check
  check (action in ('view', 'open', 'not_interested', 'reported', 'share'));

-- The repeat check, and the foreign key's index Supabase's speed check asked for.
create index feed_actions_item_user_idx on public.feed_actions (item_id, user_id);

-- Security definer: nobody reads this table through the API, the caller included.
create or replace function private.feed_actions_once_a_day()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (select 1 from public.feed_actions a
             where a.item_id = new.item_id and a.user_id = new.user_id and a.action = new.action
               and (a.at at time zone 'America/Chicago')::date = (new.at at time zone 'America/Chicago')::date) then
    return null;
  end if;
  return new;
end
$$;
revoke execute on function private.feed_actions_once_a_day() from public, anon, authenticated;

create trigger feed_actions_once_a_day
  before insert on public.feed_actions
  for each row execute function private.feed_actions_once_a_day();
