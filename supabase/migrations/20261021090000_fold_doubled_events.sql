-- Three events listed twice on Town, found checking every event against its own page on
-- 2026-10-20. Jesse, 2026-10-21: keep the place's own listing. Each copy becomes a mention on
-- the kept event, so its source reading it again lands there (write_judged's by_uid) instead of
-- making it twice; nobody had RSVPed, saved or liked either copy.

-- Outdoor U's print making, Nov 20 10 to 4: the City's calendar lists it as "Print Making
-- Workshop" (EID 2443).
-- Outdoor U's wreath making, Nov 30 4:30 to 6: the City lists it at 12:30 (EID 2444), which
-- Outdoor U's own page gives to Dec 1 and Dec 2, not Nov 30.
-- The gallery reception for Emily Sheehan's "Reflection", Oct 28 5 to 7: the campus calendar's
-- (4757014) stays; the fine-arts page's copy goes.
insert into public.event_mentions (event_id, source_name, source_url, source_uid, trust, sure, first_seen)
select keep, m.source_name, m.source_url, m.source_uid, m.trust, m.sure, m.first_seen
from (values ('9267ef80-25d5-4816-ad9c-71896994da29'::uuid, '2d57798a-f467-4dbc-a399-b2824184f43a'::uuid),
             ('aaa92df3-a11f-464c-8d72-4a023f825301'::uuid, '2e5ab46e-ed1e-48b7-a395-53ac651171a8'::uuid))
     as fold(keep, copy)
join public.event_mentions m on m.event_id = fold.copy;

insert into public.event_mentions (event_id, source_name, source_url, source_uid, trust, sure)
select '114c9836-5473-4cbd-9c3a-458660f7c5a8', 'CSB SJU', 'https://www.csbsju.edu/fine-arts/visual-arts/',
       'board:a213637c-053d-4ed5-b058-f27a63274d6b', 'official', true
where exists (select 1 from public.club_events where id = '114c9836-5473-4cbd-9c3a-458660f7c5a8');

-- Their mentions, RSVPs and the rest go with them (every reference cascades).
delete from public.club_events
where id in ('2d57798a-f467-4dbc-a399-b2824184f43a', '2e5ab46e-ed1e-48b7-a395-53ac651171a8',
             '09db24ed-d9e3-4199-8261-781d6c97bc79');
