-- ============================================================================
-- Season-aware touch picking.
--
-- The bank is seasonal by nature -- shovelling, sweet corn, ice-out -- and a
-- strict oldest-unused picker will hand you "How cold before you plug the car
-- in?" on a 91-degree August morning. The daily touch is the one module whose
-- job is to feel written by a neighbour rather than emitted by a job, so a
-- wrong-season prompt costs more than a repeated one.
--
-- Seasonal rows are preferred inside their own season and skipped outside it;
-- rows tagged 'any' carry the rest of the year. If a season runs dry the picker
-- falls back to 'any' rather than stalling.
-- ============================================================================

alter table public.daily_touches
    add column if not exists season text not null default 'any'
        check (season in ('any', 'winter', 'spring', 'summer', 'fall'));

update public.daily_touches set season = 'winter' where prompt in (
    'First real snow of the season. What''s your move?',
    'Correct time to put the outdoor lights up:',
    'Snow emergency parking: how do you find out?',
    'Winter windshield method:',
    'How cold before you plug the car in?',
    'The correct number of blankets in a Minnesota winter:',
    'Best winter comfort move:',
    'Shoveling philosophy:'
);

update public.daily_touches set season = 'spring' where prompt in (
    'It''s 34 and sunny in March. You are:',
    'First 50-degree day in spring. You:',
    'Ice-out prediction. When does it go?',
    'The first robin means:'
);

update public.daily_touches set season = 'summer' where prompt in (
    'Best sound of a St. Joe summer:',
    'How do you take your sweet corn?',
    'Garage door: open or closed?',
    'The bonfire is lit. Your seat:',
    'Best way to spend a 78-degree Saturday:',
    'Farmers market strategy:',
    'Sweet corn season: how many ears is too many?',
    'Best local swimming decision:',
    'The grill comes out when:'
);

update public.daily_touches set season = 'fall' where prompt in (
    'How do you feel about November?'
);

create index if not exists daily_touches_unused_season_idx
    on public.daily_touches (season, created_at)
    where used_on is null;

-- Meteorological seasons, which is what the copy assumes: Dec-Feb winter,
-- Mar-May spring, Jun-Aug summer, Sep-Nov fall.
create or replace function public.season_of(p_date date)
returns text
language sql
immutable
as $$
    select case extract(month from p_date)::int
               when 12 then 'winter' when 1 then 'winter' when 2 then 'winter'
               when 3 then 'spring'  when 4 then 'spring' when 5 then 'spring'
               when 6 then 'summer'  when 7 then 'summer' when 8 then 'summer'
               else 'fall'
           end;
$$;
