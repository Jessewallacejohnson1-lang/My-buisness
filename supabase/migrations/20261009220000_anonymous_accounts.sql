-- Anonymous accounts (BP app docs/plans/real-life-actions, ticket 01). Every install gets
-- one quietly through Supabase's anonymous sign-in, so Going, Save and Heart work before
-- sign-in exists. Anonymous users take the authenticated role, so every rule that admits
-- authenticated admits them too. These restrictive rules keep them from publishing what
-- other neighbours read: events and posts, clubs, comments, and uploaded photos. Their own
-- Going, saves, hearts, follows, club memberships and profile stay open to them, through
-- the rules already there. Apply this before anonymous sign-in is switched on.

create or replace function public.is_real_account()
returns boolean
language sql
stable
set search_path = public
as $$
  select coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
$$;

grant execute on function public.is_real_account() to anon, authenticated;

create policy "real accounts publish events" on public.club_events
  as restrictive for insert to authenticated
  with check ((select public.is_real_account()));

create policy "real accounts start clubs" on public.clubs
  as restrictive for insert to authenticated
  with check ((select public.is_real_account()));

create policy "real accounts comment" on public.event_comments
  as restrictive for insert to authenticated
  with check ((select public.is_real_account()));

-- Profile photos and event images are public files: a real account's only.
create policy "real accounts upload photos" on storage.objects
  as restrictive for insert to authenticated
  with check (bucket_id not in ('avatars', 'event-images') or (select public.is_real_account()));

create policy "real accounts replace photos" on storage.objects
  as restrictive for update to authenticated
  using (bucket_id not in ('avatars', 'event-images') or (select public.is_real_account()));

-- Found in the same review: the briefing writer ran for anyone with the public key. Only
-- the nightly job, which runs as postgres, calls it.
revoke execute on function public.compose_briefing(date, jsonb, text, text, text)
  from public, anon, authenticated;
