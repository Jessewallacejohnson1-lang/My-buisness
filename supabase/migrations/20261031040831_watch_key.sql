-- The Watch key's role (BP app docs/plans/loopholes/issues/12-watch-key.md). The four cloud
-- routines (morning, social, photos, accounts) read pages strangers wrote, so the key they hold
-- can do only what their scripts do: read what they read, and add or update Events, News, photos,
-- reports and the registry's pages. It deletes nothing but the day's standouts, and it can't
-- reach sign-in accounts, neighbours' posts, the waitlist, or any other table or bucket.
-- The key is a JWT naming this role, kept as the cloud environment's network secret, so the run
-- never holds it. Each grant is a script's call (BP app loopholes/assets/02-limited-key-facts.md);
-- supabase/tests/watch_saves.test.mjs makes every save as this role, and tries the break-ins.

do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'watch') then
    create role watch nologin;
  end if;
  -- The Data API and Storage take on a request's role through authenticator (not in the tests).
  if exists (select 1 from pg_roles where rolname = 'authenticator') then
    grant watch to authenticator;
  end if;
end $$;

-- private: the triggers on club_events and board_items, and event_picture's helpers.
grant usage on schema public, private to watch;

-- Reads. Of neighbours' Going and likes only the Event, never who.
grant select on public.club_events, public.event_mentions, public.board_items, public.teams, public.sources,
  public.place_photos, public.places, public.daily_standouts, public.morning_reports to watch;
grant select (id, name) on public.clubs to watch;
grant select (event_id) on public.event_rsvps, public.event_likes to watch;

-- Writes: apply_judged's Events, mentions, News and teams; tags, Abouts, photo checks and map spots;
-- the registry's pages; the standouts, rewritten each morning; the report; photos; Google's hours.
grant insert, update on public.club_events, public.event_mentions, public.board_items, public.sources,
  public.morning_reports to watch;
grant insert on public.teams, public.place_photos, public.daily_standouts to watch;
grant delete on public.daily_standouts to watch;
grant update (hours) on public.places to watch;
grant execute on function public.apply_judged(jsonb, jsonb, jsonb, jsonb, jsonb, jsonb),
  public.listed_for_writer(), public.event_picture(uuid) to watch;

-- Row security: every row of the tables above; the grants say what it may do there. Keep each a
-- plain `true`: beside it Postgres drops the neighbours' rules written for every role ("moderate
-- events", "admin update places"), which call is_admin(), and this role may not run that (it has
-- no schema auth).
create policy "watch rows" on public.club_events to watch using (true) with check (true);
create policy "watch rows" on public.event_mentions to watch using (true) with check (true);
create policy "watch rows" on public.board_items to watch using (true) with check (true);
create policy "watch rows" on public.teams to watch using (true) with check (true);
create policy "watch rows" on public.sources to watch using (true) with check (true);
create policy "watch rows" on public.place_photos to watch using (true) with check (true);
create policy "watch rows" on public.places to watch using (true) with check (true);
create policy "watch rows" on public.daily_standouts to watch using (true) with check (true);
create policy "watch rows" on public.morning_reports to watch using (true) with check (true);
create policy "watch rows" on public.clubs for select to watch using (true);
create policy "watch rows" on public.event_rsvps for select to watch using (true);
create policy "watch rows" on public.event_likes for select to watch using (true);

-- Storage: new files in the places bucket only, never overwritten (db.py sends x-upsert: false).
grant usage on schema storage to watch;
grant select, insert on storage.objects to watch;
create policy "watch uploads place photos" on storage.objects for insert to watch
  with check (bucket_id = 'places');
