-- Two schools to follow from onboarding's Schools (BP app onboarding 28; Jesse's yes, 2026-11-04).
-- Their own Events link by source_name, with no team on them, so a team row wouldn't lift them and a
-- page, which follows its source (`my_pages`), does. St. John's Prep uses the crest its team already
-- has; St. Joseph Catholic has none yet, so its tile shows its initials.
insert into public.town_pages (town, slug, name, kind, source_name, picture, picture_kind)
values ('st-joseph-mn', 'st-johns-prep', 'St. John''s Prep', 'School', 'St. John''s Prep',
        'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/teams/st-johns-prep/logo-42258211c8.png', 'logo'),
       ('st-joseph-mn', 'st-joseph-catholic', 'St. Joseph Catholic School', 'School', 'St. Joseph Catholic School',
        null, null)
on conflict (town, slug) do nothing;
