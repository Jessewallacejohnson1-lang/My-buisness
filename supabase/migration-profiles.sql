-- Korina profiles migration
-- Run in: Supabase Dashboard → SQL Editor → New query → paste → Run
--
-- One row per user: onboarding answers + the daily targets computed from them.

create table if not exists public.profiles (
  user_id        uuid primary key default auth.uid(),
  sex            text not null,           -- 'male' | 'female' | 'unspecified'
  age            int  not null,
  height_cm      numeric not null,
  weight_kg      numeric not null,
  activity       text not null,           -- 'sedentary' | 'light' | 'active' | 'very_active'
  goal           text not null,           -- 'lose' | 'maintain' | 'build' | 'clean'
  pace           text not null,           -- 'gentle' | 'moderate' | 'aggressive'
  diet           text not null,           -- 'none' | 'vegetarian' | 'vegan' | 'pescatarian' | 'paleo' | 'keto' | 'mediterranean'
  training_days  int  not null,
  goal_calories  int  not null,
  goal_protein   int  not null,
  goal_carbs     int  not null,
  goal_fat       int  not null,
  goal_fibre     int  not null,
  focus          text[] not null default '{}',
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

-- Safe to re-run: adds the focus column to an already-created table.
alter table public.profiles add column if not exists focus text[] not null default '{}';

alter table public.profiles enable row level security;

drop policy if exists "own profile" on public.profiles;
create policy "own profile" on public.profiles
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
