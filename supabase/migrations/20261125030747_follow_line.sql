-- The line Follow 3 shows its places in (BP app community-value 04). A place's `follow_spot` holds its spot, 1 first, and
-- its `fit`: where it stands for somebody who picked an interest it fits; with a fit alone it is in line for them only.
-- `group` and `late` shape the first circles. The Town's own pages can stand in it too. The line is remade on the 1st of
-- each month by the cloud's role; the photo a circle shows is picked by hand and stays.
alter table public.places drop constraint places_follow_spot_shape;

create function private.is_follow_spot(p jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p is null or (jsonb_typeof(p) = 'object'
    and coalesce(jsonb_typeof(p -> 'spot'), 'null') in ('number', 'null')
    and coalesce(jsonb_typeof(p -> 'fit'), 'null') in ('number', 'null')
    and coalesce(p ->> 'spot', '1') ~ '^[1-9][0-9]*$' and coalesce(p ->> 'fit', '1') ~ '^[1-9][0-9]*$'
    and coalesce(jsonb_typeof(p -> 'group'), 'null') in ('string', 'null')
    and coalesce(jsonb_typeof(p -> 'late'), 'null') in ('boolean', 'null')
    and coalesce(jsonb_typeof(p -> 'photo'), 'null') in ('string', 'null')
    and p - array['spot', 'fit', 'group', 'late', 'photo'] = '{}');
$$;

alter table public.places
  add constraint places_follow_spot_shape check (private.is_follow_spot(follow_spot));
alter table public.town_pages
  add column follow_spot jsonb constraint town_pages_follow_spot_shape check (private.is_follow_spot(follow_spot));

comment on column public.places.follow_spot is
  'Where it stands in line in onboarding''s Follow 3: {"spot": 1, "fit": 1, "group": "food", "late": false, "photo": url or null}.';
comment on column public.town_pages.follow_spot is 'As places.follow_spot.';

-- Saves a whole line: [{"id": a place's, or "page": a slug, "spot", "fit", "group", "late"}]. A place keeps its photo
-- unless its row names one, out of the line too; whatever is not in the line has no spot. A line that is short, or with a row
-- that is no place's and no page's or is there twice, is a broken run's: refused whole. Returns how many stand in it.
create function public.save_follow_line(p_line jsonb)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  n int;
  m int;
begin
  if jsonb_typeof(p_line) is distinct from 'array' or jsonb_array_length(p_line) < 100 then
    raise exception 'a line of fewer than 100 is not saved';
  end if;
  if (select count(x ->> 'spot') <> count(distinct x ->> 'spot') or min((x ->> 'spot')::int) is distinct from 1
      from jsonb_array_elements(p_line) x) then
    raise exception 'a line starts at spot 1, and no two share a spot';
  end if;
  if (select count(distinct coalesce(p.id, g.id)) from jsonb_array_elements(p_line) x
      left join public.places p on p.id::text = x ->> 'id'
      left join public.town_pages g on g.slug = x ->> 'page') <> jsonb_array_length(p_line) then
    raise exception 'every row of a line is one place or one page, once';
  end if;
  update public.places p
  set follow_spot = new.spot
  from (
    select q.id, case
        when x is not null then
          jsonb_strip_nulls(jsonb_build_object('spot', x -> 'spot', 'fit', x -> 'fit', 'group', x -> 'group', 'late', x -> 'late'))
          || jsonb_build_object('photo', case when x ? 'photo' then x -> 'photo' else q.follow_spot -> 'photo' end)
        when q.follow_spot ->> 'photo' is not null then jsonb_build_object('photo', q.follow_spot -> 'photo')
      end as spot
    from public.places q
    left join jsonb_array_elements(p_line) x on x ->> 'id' = q.id::text and q.closed_at is null) new
  where new.id = p.id and p.follow_spot is distinct from new.spot;
  update public.town_pages g
  set follow_spot = new.spot
  from (
    select q.id, case when x is not null then
        jsonb_strip_nulls(jsonb_build_object('spot', x -> 'spot', 'fit', x -> 'fit', 'group', x -> 'group', 'late', x -> 'late')) end as spot
    from public.town_pages q
    left join jsonb_array_elements(p_line) x on x ->> 'page' = q.slug) new
  where new.id = g.id and g.follow_spot is distinct from new.spot;
  select count(*) into n from public.places where follow_spot ? 'fit';
  select count(*) into m from public.town_pages where follow_spot ? 'fit';
  return n + m;
end
$$;
revoke all on function public.save_follow_line(jsonb) from public, anon, authenticated;
grant execute on function public.save_follow_line(jsonb) to watch, service_role;

-- What the line is made from, beside `place_facts`: each open place's kind, and each Town page's upcoming Events.
create function public.follow_line_facts()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'kinds', (select coalesce(jsonb_object_agg(p.id, p.primary_type), '{}') from public.places p where p.closed_at is null),
    'pages', (select coalesce(jsonb_agg(jsonb_build_object('slug', g.slug, 'name', g.name, 'events',
        (select count(distinct e.title) from public.club_events e
         where e.source_name = g.source_name and e.status = 'approved' and e.cancelled_at is null
           and e.event_date >= (now() at time zone 'America/Chicago')::date)) order by g.slug), '[]') from public.town_pages g));
$$;
revoke all on function public.follow_line_facts() from public, anon, authenticated;
grant execute on function public.follow_line_facts() to watch, service_role;
