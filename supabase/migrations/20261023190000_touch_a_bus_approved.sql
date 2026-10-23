-- Trobec's Touch A Bus was held for no time or place; its Facebook event gives both (Jesse's yes, 2026-10-23).
update public.club_events
set status = 'approved',
    start_time = '10 AM',
    all_day = false,
    end_at = '2026-10-24 12:00:00-05',
    location = 'Trobec''s Bus Service',
    source_url = 'https://www.facebook.com/events/1130297482858426/',
    interests = array['families_kids']
where id = 'a1582885-4218-40d6-abdf-2d604d7fd3ed';
