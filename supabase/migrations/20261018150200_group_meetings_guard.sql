-- A mistyped meeting rule costs only itself (BP app rsvp-and-groups 05, from its review). In
-- 20261018150000_groups.sql a rule whose days weren't a list, or a week that wasn't a number, made
-- group_meetings error, and with it get_groups: the whole Groups shelf stayed a skeleton. Now a rule
-- that isn't an object, days that aren't a list, and weeks or months that aren't numbers are left
-- out, and a time that isn't text reads as no time. Stable, not immutable: its day-by-day walk runs
-- in the database's time zone. Otherwise line for line the first version.
create or replace function public.group_meetings(p_meets jsonb, p_from date, p_n int default 3)
returns jsonb
language sql
stable
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object('what', m.what, 'day', m.day, 'time', m.time, 'where', m.place)
                            order by m.day, m.time), '[]'::jsonb)
  from (
    select r->>'what' as what, to_char(d, 'YYYY-MM-DD') as day,
           case when jsonb_typeof(r->'time') = 'string' then r->>'time' end as time,
           case when jsonb_typeof(r->'where') = 'string' then r->>'where' end as place
    from jsonb_array_elements(case when jsonb_typeof(p_meets) = 'array' then p_meets else '[]'::jsonb end) r
    cross join generate_series(p_from, p_from + 120, interval '1 day') d
    where jsonb_typeof(r) = 'object'
      and jsonb_typeof(r->'days') = 'array'
      and to_char(d, 'dy') in (select jsonb_array_elements_text(r->'days'))
      and (jsonb_typeof(r->'weeks') is distinct from 'array'
           or ((extract(day from d)::int - 1) / 7 + 1) in
              (select w::text::numeric::int from jsonb_array_elements(r->'weeks') w where jsonb_typeof(w) = 'number'))
      and extract(month from d)::int not in
          (select mo::text::numeric::int
             from jsonb_array_elements(case when jsonb_typeof(r->'months_off') = 'array'
                                            then r->'months_off' else '[]'::jsonb end) mo
            where jsonb_typeof(mo) = 'number')
    order by 2, 3
    limit p_n
  ) m
$$;
