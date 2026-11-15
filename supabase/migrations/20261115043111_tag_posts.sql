-- A #tag's own page (BP app town-feed 63; mock https://claude.ai/artifact/MbsdhHE9YETGJhs9s2LhZ3, Jesse 2026-11-14:
-- "yes, I agree to all"). Tapping a #tag in a neighbour's post opens a page of every post that carries it, newest
-- first, at any age (the Town feed keeps a post 7 days). The rows are the bell's `get_my_mentions` rows, a post as the
-- Town feed sends it, so the app reads them with the feed's own decoder.
--
-- Who sees what is the Town feed's `posts` rule: approved posts, never one from a poster you blocked or who blocked
-- you (`private.shows_poster`), muted or hidden by you; a Friends-only post only for the poster and their friends,
-- kept away by club_events' own read rule (security invoker). Posts carry no town yet, as in the feed.
--
-- The tag matches as the app finds one (`PostWords.tags`): `#` at the words' start or after a space, the tag, then the
-- end or something that isn't a letter, digit or `_`; case ignored. A tag that isn't only letters, digits and `_`
-- gets no rows, so nothing else ever reaches the pattern.
create or replace function public.get_tag_posts(p_tag text)
returns table (
  id uuid,
  title text,
  location text,
  image_url text,
  created_at timestamptz,
  leaves_at timestamptz,
  heart_count int,
  hearted boolean,
  kind text,
  poster jsonb
)
language sql
stable
security invoker
set search_path = ''
as $$
  select e.id, e.title, e.location, e.image_url, e.created_at, e.created_at + interval '7 days',
         private.heart_count(e.id),
         exists (select 1 from public.event_likes h where h.event_id = e.id and h.user_id = auth.uid()),
         'post'::text,
         pp.poster || jsonb_strip_nulls(jsonb_build_object('aspect', e.image_aspect, 'more_photos', e.more_photos,
                                                           'friends_only', e.friends_only,
                                                           'at_names', private.post_at_names(e.at_names)))
  from public.club_events e
  cross join lateral (select private.post_poster(e.submitted_by, e.tagged) as poster) pp
  where p_tag ~ '^[[:alnum:]_]{1,100}$'
    and e.kind = 'post' and e.status = 'approved'
    and e.created_at <= now()
    and e.title ~* ('(^|\s)#' || p_tag || '($|[^[:alnum:]_])')
    and private.shows_poster(e.submitted_by)
    and not exists (select 1 from public.feed_mutes m where m.user_id = auth.uid() and m.host = e.submitted_by::text)
    and not exists (select 1 from private.my_not_interested() n where n.item_id = e.id)
    and pp.poster is not null
  order by e.created_at desc, e.id
  limit 200
$$;
revoke execute on function public.get_tag_posts(text) from public;
grant execute on function public.get_tag_posts(text) to anon, authenticated;
