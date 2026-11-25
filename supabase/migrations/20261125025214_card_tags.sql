-- Every Event's and News's fine tags (poetry, polka, author talk), kept where no one in the app can read them (BP app
-- docs/plans/feed-learns, ticket 03; Jesse, 2026-11-24). Not a column on club_events or board_items: the app's public
-- key reads those. `tagged` there means people tagged and `tags` in the Town feed means Interests, so these are card tags.
--
--   private.tags             the one shared list: each word, when it was made, and the two that agreed.
--   private.card_tags        each Event's or News's words, all from the list.
--   public.tag_work          the list, and the upcoming Events and the News that have no tags yet.
--   public.save_card_tags    saves new words, then cards. A word not on the list is left off its card, and a card left with
--                            none is done: it is not asked about again.
--
-- Only the cloud routines (watch) and the service key may call the two public functions. Neither reaches a post: the
-- Watch key is closed to those (watch_never_posts), and these see only kind = 'event'.
--
-- Roll back: drop function public.save_card_tags(jsonb, jsonb), public.tag_work(); drop table private.card_tags, private.tags.

create table private.tags (
  word text primary key check (word ~ '^[[:alnum:]][[:alnum:] ''&-]{0,28}[[:alnum:]]$' and word !~ '  '),
  made_at timestamptz not null default now(),
  first_by text not null check (btrim(first_by) <> ''),
  second_by text not null check (btrim(second_by) <> ''),
  check (first_by <> second_by)
);
create unique index tags_one_spelling_idx on private.tags (lower(word));

create table private.card_tags (
  id bigint generated always as identity primary key,
  event_id uuid unique references public.club_events (id) on delete cascade,
  news_id uuid unique references public.board_items (id) on delete cascade,
  words text[] not null,  -- empty: looked at, and nothing fits
  tagged_at timestamptz not null default now(),
  check (num_nonnulls(event_id, news_id) = 1)
);

alter table private.tags enable row level security;
alter table private.card_tags enable row level security;
revoke all on private.tags, private.card_tags from public, anon, authenticated, watch;

create function public.tag_work()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with town as (select (now() at time zone 'America/Chicago')::date as today),
  events as (
    select e.id, e.title, coalesce(c.name, e.source_name, '') as host, coalesce(e.location, '') as place,
           left(btrim(regexp_replace(coalesce(e.description, ''), '\s+', ' ', 'g')), 300) as about, e.category, e.sport,
           e.event_date
    from public.club_events e
    cross join town
    left join public.clubs c on c.id = e.club_id
    where e.status = 'approved' and e.kind = 'event' and e.cancelled_at is null
      and (e.event_date >= town.today or (e.end_at at time zone 'America/Chicago')::date >= town.today)
      and not exists (select 1 from private.card_tags t where t.event_id = e.id)
  ),
  news as (
    select b.id, b.title, coalesce(b.source_name, '') as host,
           left(btrim(regexp_replace(coalesce(b.blurb, ''), '\s+', ' ', 'g')), 300) as about, b.category,
           b.created_at, b.published_at, b.posted_at, b.starts_at, b.ends_on
    from public.board_items b
    where b.status = 'published' and b.published_at > now() - interval '30 days'
      and not exists (select 1 from private.card_tags t where t.news_id = b.id)
  )
  select jsonb_build_object(
    'words', (select coalesce(jsonb_agg(word order by lower(word)), '[]') from private.tags),
    'events', (select coalesce(jsonb_agg(to_jsonb(events) order by event_date, id), '[]') from events),
    'news', (select coalesce(jsonb_agg(to_jsonb(news) order by published_at desc, id), '[]') from news));
$$;
revoke all on function public.tag_work() from public, anon, authenticated;
grant execute on function public.tag_work() to watch, service_role;

create function public.save_card_tags(p_words jsonb, p_cards jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  given jsonb;  -- each card's words as the list spells them, once each, in the order given
  made int;
  events int;
  news int;
begin
  insert into private.tags (word, first_by, second_by)
  select x ->> 'word', x ->> 'first_by', x ->> 'second_by' from jsonb_array_elements(p_words) x
  on conflict do nothing;
  get diagnostics made = row_count;

  select coalesce(jsonb_agg(jsonb_build_object('kind', x ->> 'kind', 'id', x ->> 'id', 'words', coalesce(w.words, '[]'))), '[]') into given
  from jsonb_array_elements(p_cards) x
  cross join lateral (
    select jsonb_agg(once.word order by once.at) as words
    from (select t.word, min(g.at) as at
          from jsonb_array_elements_text(x -> 'words') with ordinality as g (word, at)
          join private.tags t on lower(t.word) = lower(g.word)
          group by t.word) once
  ) w;

  insert into private.card_tags (event_id, words)
  select e.id, array(select v from jsonb_array_elements_text(x -> 'words') with ordinality as g (v, at) order by at)
  from jsonb_array_elements(given) x
  join public.club_events e on e.id = (x ->> 'id')::uuid and e.kind = 'event'
  where x ->> 'kind' = 'event'
  on conflict (event_id) do update set words = excluded.words, tagged_at = now();
  get diagnostics events = row_count;

  insert into private.card_tags (news_id, words)
  select b.id, array(select v from jsonb_array_elements_text(x -> 'words') with ordinality as g (v, at) order by at)
  from jsonb_array_elements(given) x
  join public.board_items b on b.id = (x ->> 'id')::uuid
  where x ->> 'kind' = 'news'
  on conflict (news_id) do update set words = excluded.words, tagged_at = now();
  get diagnostics news = row_count;

  return jsonb_build_object('words', made, 'events', events, 'news', news,
                            'list', (select count(*) from private.tags));
end
$$;
revoke all on function public.save_card_tags(jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.save_card_tags(jsonb, jsonb) to watch, service_role;
