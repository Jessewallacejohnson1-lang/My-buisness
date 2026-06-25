-- Clubs: remove the old seeded placeholder data + add detail fields.
-- Run once in the Supabase SQL editor.

-- 1. Delete the 5 fake seeded clubs (matched by their placeholder name + host).
--    club_events.club_id is ON DELETE CASCADE, so their fake events go too.
delete from public.clubs
where (name, host) in (
  ('Saturday Run Club', 'Marcus T.'),
  ('Yoga in the Park',  'Sarah K.'),
  ('Trivia Night',      'Bad Habit Bar'),
  ('Book Club',         'Anna R.'),
  ('Cold Plunge Club',  'Jesse V.')
);

-- 2. Sweep any orphaned seeded town events (club_id null) by their exact titles.
delete from public.club_events
where club_id is null
  and title in ('Run Club at Riverside', 'Yoga in the Park', 'Trivia at Bad Habit',
                'Farmers Market', 'Run Club', 'Trivia Night', 'Book Club');

-- 3. Detail fields for the club detail view (where / about / what to expect).
alter table public.clubs
  add column if not exists location     text,
  add column if not exists description  text,
  add column if not exists expectations text;
