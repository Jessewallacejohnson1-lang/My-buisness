-- The old Hygge wellness app's three tables. Block Party never read them: no app, edge
-- function, view, trigger, foreign key or function refers to them (checked live 2026-10-22).
-- Jesse, 2026-10-22: "Hygge can go ... delete permanently."
drop table if exists public.food_logs;
drop table if exists public.workouts;
drop table if exists public.profiles;
