-- Misreads of 2026-11-23, corrected on Jesse's yes the same day ("yes to all"; BP app watch-every-place 43, 44, 45).
do $$
begin
  -- A correction is no move: no card says it moved and nobody is told.
  alter table public.club_events disable trigger club_events_moved;

  -- 43: the judge wrote the winter offset on days after the March clock change, so each came in an hour late. Each clock
  -- below is the host's own page, read 2026-11-23 (the Lions Club: "6 pm"; Outdoor U: 6-8 p.m., 1:00-2:30 pm, 5:30 am to
  -- 12:00 pm; the Sisters: 11:30 am to 12:45 pm). The made-up id carries the clock, so it goes back too.
  with fixed (id, start_time, was, now) as (values
    ('22099a68-7fd0-4372-a455-8217364025f9'::uuid, '6 PM', 'T1900', 'T1800'),     -- Lions, Mar 16
    ('355f5ea4-6bc7-4696-951d-a9184440bd56', '6 PM', 'T1900', 'T1800'),           -- Lions, Apr 6
    ('645ad6bb-78c4-4a01-9a97-5ccdc21860ce', '6 PM', 'T1900', 'T1800'),           -- Lions, Apr 20
    ('7c029e58-e7e1-456d-bb09-6ede930921fd', '6 PM', 'T1900', 'T1800'),           -- Lions, May 4
    ('d8c1114f-0fe8-44e6-a980-bd80dba7bbef', '6 PM', 'T1900', 'T1800'),           -- Lions, May 18
    ('731cf05d-0e62-4cb5-bac8-79301793ef31', '6 PM', 'T1900', 'T1800'),           -- Lions, Jun 1
    ('20a4f8b6-af0e-4348-94e7-264a2558c3cd', '6 PM', 'T1900', 'T1800'),           -- Lions, Jun 15
    ('63056f57-3539-4cef-afa3-9395779ba283', '6 PM', 'T1900', 'T1800'),           -- Lions, Jul 6
    ('fd264bcd-760c-437f-95fb-bcbfb5b9f143', '6 PM', 'T1900', 'T1800'),           -- Lions, Jul 20
    ('874badd1-0b24-433f-85fd-f9cd65876ce1', '6 PM', 'T1900', 'T1800'),           -- Paddle Making Workshop, Mar 19
    ('3ee23403-8ec6-457a-9af7-2a8ad883dfe1', '1 PM', 'T1400', 'T1300'),           -- Funky Frogs and Cool Pools, Apr 17
    ('57e1bfdb-1e5b-4ae3-bc9f-4918464dfcc3', '5:30 AM', 'T0630', 'T0530'),        -- Bob Russell Spring Birding Day, May 8
    ('80517219-c1c4-4e0c-ba6f-7196c5f58e75', '11:30 AM', 'T1230', 'T1130')),      -- Lenten Sacred Pause, Mar 18
  events as (
    update public.club_events e
    set start_time = f.start_time, end_at = e.end_at - interval '1 hour', source_uid = replace(e.source_uid, f.was, f.now)
    from fixed f where e.id = f.id and e.source_uid like '%' || f.was || '%'
    returning e.id)
  update public.event_mentions m
  set source_uid = replace(m.source_uid, f.was, f.now)
  from fixed f where m.event_id = f.id and m.source_uid like 'page:%' || f.was || '%';

  -- 45: back on where its listing puts it ("Advent Reconciliation Service/St. John the Baptist").
  update public.club_events
  set status = 'approved', review_reason = null, location = 'St. John the Baptist Church',
      place_entry_id = 'st-john-baptist-parish', lat = 45.58365, lng = -94.40224, moved_at = null, moved_from = null
  where id = 'e92df612-059e-4ecb-b3d1-22173bd20425' and event_date = '2026-12-12';

  alter table public.club_events enable trigger club_events_moved;
end $$;

-- Intergenerational Bingo, Feb 3: the page lists it once, so "a weekly Wednesday event" comes out of its About.
update public.club_events
set description = 'A bingo night for all ages at the Church of St. Joseph. The church''s calendar page also lists Ignite Youth Night for grades 6 to 12 in the same slot.'
where id = 'c4144606-a9da-4f4d-aef6-85d862542bed';

-- 44: two evenings with "Holiday" in their names came in as News. Each is an Event now, so its News leaves.
update public.board_items set status = 'archived'
where id in ('bbac6b1f-ebca-4aea-8298-eb021b9dd84a',   -- Holiday Hope Event, Dec 8
             'ed440a80-59b2-4749-842a-b859b361919d');  -- Holiday Crafts!, Dec 15

-- Back with the district's own words: 9 PM only when it can, else 5:15 to 6 AM.
update public.board_items set status = 'published', blurb = 'Word by 9 PM if they can, else 5:15 to 6 AM.'
where id = 'bf15ae3b-9ddc-4a2b-8b7a-58aec5cf37a0';
