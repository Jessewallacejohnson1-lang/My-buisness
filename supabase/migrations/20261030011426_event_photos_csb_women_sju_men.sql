-- Event photos (BP app docs/plans/event-photos 07, Jesse 2026-10-29): CSB's teams are women's and SJU's are
-- men's, so "CSB Hockey" is a girls' game and "SJU Hockey" a boys' one, though neither title says so. Both
-- sit on CSB's athletics page, so a Bennies photo must never land on a Johnnies game. A title naming both
-- (a joint concert) names neither.

create or replace function private.event_gender(p_title text, p_sport text)
returns text
language sql
immutable
as $$
  select case
    when x ~ '\y(girls|women|womens|women''s|lady|ladies)\y' then 'girls'
    when x ~ '\y(boys|men|mens|men''s)\y' then 'boys'
    when x ~ '\y(csb|bennies|blazers)\y|\ys(ain)?t\.? benedict' and x !~ '\y(sju|johnnies)\y' then 'girls'
    when x ~ '\y(sju|johnnies)\y' and x !~ '\y(csb|bennies|blazers)\y|\ys(ain)?t\.? benedict' then 'boys'
  end
  from (select lower(coalesce(p_sport, '') || ' ' || coalesce(p_title, '')) as x) t
$$;
