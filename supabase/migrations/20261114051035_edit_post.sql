-- Edit a post (BP app town-feed 44, references/edit-post; Jesse at Check-in 1, 2026-11-13: "i agree"). A neighbour
-- changes their own live post's words and Place; its photo, who can see it and who it's with stay. The edit goes
-- through the same instant check a new post does (moderate-post's `edit`), and nothing is written until the check says
-- yes, so everyone keeps the old words until then. The "moderate events" update rule already shuts a live post to the
-- poster's own writes (20261101203718_town_plus_posting.sql), so these two functions, for the check alone, are the
-- only way in, and they write three columns.
--
-- Roll back: drop function public.apply_post_edit(uuid, uuid, text, text, jsonb);
--            drop function public.claim_edit(uuid, uuid, text, text); drop table private.post_edit_checks;

-- 1. One row per edit the check reads: at most 10 a day each (a new post's cap, counted apart), and the words and
-- Place the edit replaced, so Jesse's Review of a reported post can still see what was reported.
create table if not exists private.post_edit_checks (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  event_id uuid not null references public.club_events (id) on delete cascade,
  at timestamptz not null default now(),
  old_title text,
  old_location text
);
create index if not exists post_edit_checks_user_at on private.post_edit_checks (user_id, at);

-- 2. The check's claim on one edit: 'claimed' when the post is p_user's own live post and the new words and Place
-- would make a post claim_submit takes (words or a photo, at most 2,000 characters; a Place of at most 120), and the
-- day's 10 aren't used; 'limit' when they are; else 'refused'.
create or replace function public.claim_edit(p_event uuid, p_user uuid, p_words text, p_place text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform pg_advisory_xact_lock(hashtextextended('claim_edit:' || p_user::text, 0));
  if (select count(*) from private.post_edit_checks where user_id = p_user and at > now() - interval '24 hours') >= 10 then
    return 'limit';
  end if;
  insert into private.post_edit_checks (user_id, event_id, old_title, old_location)
  select p_user, e.id, e.title, e.location
  from public.club_events e
  where e.id = p_event and e.submitted_by = p_user and e.kind = 'post' and e.status = 'approved'
    and char_length(coalesce(p_words, '')) <= 2000 and char_length(coalesce(p_place, '')) <= 120
    and (btrim(coalesce(p_words, '')) <> '' or e.image_url is not null);
  return case when found then 'claimed' else 'refused' end;
end
$$;
revoke execute on function public.claim_edit(uuid, uuid, text, text) from public, anon, authenticated;
grant execute on function public.claim_edit(uuid, uuid, text, text) to service_role;

-- 3. The edit the check said yes to: the words, the Place (blank is none) and the @ names, kept as claim_submit keeps
-- them (`private.checked_at_names`, at most 20 sent). Nothing else on the row moves. False when the post has gone (deleted
-- or taken down while it was checked).
create or replace function public.apply_post_edit(p_event uuid, p_user uuid, p_words text, p_place text, p_names jsonb)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.club_events e
  set title = coalesce(p_words, ''),
      location = nullif(btrim(coalesce(p_place, '')), ''),
      at_names = private.checked_at_names(p_user, coalesce(p_words, ''), p_names)
  where e.id = p_event and e.submitted_by = p_user and e.kind = 'post' and e.status = 'approved'
    and char_length(coalesce(p_words, '')) <= 2000 and char_length(coalesce(p_place, '')) <= 120
    and (btrim(coalesce(p_words, '')) <> '' or e.image_url is not null)
    and (p_names is null or jsonb_typeof(p_names) <> 'array' or jsonb_array_length(p_names) <= 20);
  return found;
end
$$;
revoke execute on function public.apply_post_edit(uuid, uuid, text, text, jsonb) from public, anon, authenticated;
grant execute on function public.apply_post_edit(uuid, uuid, text, text, jsonb) to service_role;
