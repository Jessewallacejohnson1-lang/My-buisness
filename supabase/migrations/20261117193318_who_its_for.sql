-- Who each Event is for (BP app inside-cards 35; Jesse, 2026-11-17: "i want this for every event like some could be
-- family event", then "if it's not certain, it can be more broad, like for everyone", and yes to the plan).
--
-- 1. club_events.ages also takes one of five words, "Older adults", "Families", "Kids", "Teens" or "Adults", so the word
--    rides every card and shows where the age shows (inside-cards 30: "Older adults | $5" under the place, "Tue · 1 PM ·
--    Older adults" on the Town card) with no change to the cards or the app. A source's age wins: the morning's judge
--    writes an age over the word (apply_judged), and sources/scripts/audience.py writes a word only where ages is null.
-- 2. club_events.audience_at: when two helpers judged who it's for (audience.py keep), agreeing or not, so an Event is
--    judged once. Everyone, a disagreement or a doubt leaves ages null: nothing shows.
--
-- Take down one word: `update public.club_events set ages = null where id = '<id>';` (audience_at stays, so it isn't
-- judged again). Undo all: put the 20261109035346 check back after nulling the words, and drop audience_at.

alter table public.club_events drop constraint club_events_ages_shape;
alter table public.club_events add constraint club_events_ages_shape check (
  ages ~ '^([0-9]{1,2}\+|Ages [0-9]{1,2}–[0-9]{1,2}|Ages [0-9]{1,2} and under|Older adults|Families|Kids|Teens|Adults)$');

alter table public.club_events add column audience_at timestamptz;

comment on column public.club_events.ages is
  'Who it''s for: the age a source says ("21+", "Ages 6–14", "Ages 12 and under"), else the word two helpers agreed on '
  '(Older adults, Families, Kids, Teens, Adults; audience.py). Null shows nothing. BP app inside-cards 30 and 35.';
comment on column public.club_events.audience_at is
  'When two helpers judged who the Event is for (sources/scripts/audience.py keep). Null: not judged yet. BP app inside-cards 35.';
