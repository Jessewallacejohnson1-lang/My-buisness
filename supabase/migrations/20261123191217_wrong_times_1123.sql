-- Five Events at a time their own source sends wrong every morning, corrected on Jesse's yes of 2026-11-23 ("yes to all";
-- BP app backlog 39). sources/towns/st-joseph-mn.yaml's wrong_times keeps them right from the next morning run; `why` there
-- says where each right time comes from. Each update holds only while the wrong time is still there.
do $$
begin
  -- A correction is no move: no card says it moved and nobody is told.
  alter table public.club_events disable trigger club_events_moved;

  with fixed (id, was, start_time, end_at) as (values
    ('4252e289-f790-4995-b394-f5d9e84b8bc5'::uuid, '6 PM', '5:20 PM', '2026-12-03 21:00:00 America/Chicago'::timestamptz),  -- SMS Choir Concerts
    ('d8629667-b489-427a-98ca-47080fbcecaf', '6 AM', '6 PM', '2026-12-10 20:00:00 America/Chicago'),                        -- SMS Orchestra Concerts
    ('7234373c-50b9-4a72-be10-43d290c20e6e', '11 PM', '11 AM', null),                                                      -- Roseau vs River Lakes JV, Dec 12
    ('74a60b5d-857b-4ba8-a5f8-f34550a2805f', '6:30 AM', '6:30 PM', '2026-12-15 19:30:00 America/Chicago'),                  -- Benedictine Spirituality Certificate
    ('21e9ab32-d63b-4a4f-a050-11cd0c8a558a', '10 PM', '10 AM', null))                                                      -- Granite City Hockey Showcase JV, Dec 30
  update public.club_events e
  set start_time = f.start_time, end_at = f.end_at
  from fixed f where e.id = f.id and e.start_time = f.was;

  alter table public.club_events enable trigger club_events_moved;
end $$;
