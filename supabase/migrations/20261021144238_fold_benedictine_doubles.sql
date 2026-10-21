-- Two events listed twice on Town, found in the 2026-10-21 morning watch's check. The sisters'
-- own calendar (Sisters of the Order of Saint Benedict) names no place; the campus calendar lists
-- the same events under Saint Benedict's Monastery, one of their names, so the writer kept them
-- apart (it now reads no place as the poster's own: write_judged.py's where()). Jesse, 2026-10-21:
-- keep the sisters' own listing. The campus copy's mention moves onto the kept event, so the
-- campus calendar reading it again lands there (write_judged's by_uid); nobody had RSVPed, saved
-- or liked either copy. Applied live before this file was written; every statement is a no-op
-- the second time.

-- Anniversary of the Dedication of Sacred Heart Chapel, Oct 23 7 PM and Oct 24 all day
-- (campus 4770133 and 4770134).
update public.event_mentions set event_id = '09901d12-2d37-4cc4-95eb-98d4d3c127fa'
where event_id = '8f9f5dd2-3e53-47b8-9363-128f3c146ea5' and source_uid = '4770133';
update public.event_mentions set event_id = '07eb4e51-27b7-4db8-b740-01edae688999'
where event_id = '6fbcccc9-98e9-4744-b61a-7bee45779103' and source_uid = '4770134';

-- Deep Waters: A Workshop for Writers, Oct 31 9 AM (campus 4155866).
update public.event_mentions set event_id = 'e5e3e52a-d26e-417f-8b9c-40538b77b1cb'
where event_id = '87c8d677-c9d5-4a6c-bcac-437d8dba8225' and source_uid = '4155866';

delete from public.club_events
where id in ('8f9f5dd2-3e53-47b8-9363-128f3c146ea5', '6fbcccc9-98e9-4744-b61a-7bee45779103',
             '87c8d677-c9d5-4a6c-bcac-437d8dba8225')
  and source_name = 'Saint Benedict''s Monastery';

-- The morning held "Holiday sales at Art and Heritage Place" (no dates on the page); Jesse
-- published it.
update public.board_items set status = 'published', published_at = now()
where id = 'd60602cb-313d-469a-ae46-c322c59ce981' and status = 'staging';
