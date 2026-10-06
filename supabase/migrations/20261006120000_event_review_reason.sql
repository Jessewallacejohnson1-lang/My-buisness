-- What was wrong with a found event the admin declined in the Review queue (ADR-021 in the
-- registry's decision records). The share of found events declined for a misread decides
-- when found events may publish on their own: fewer than 1 in 20. Approving never clears
-- it, so a misread that was fixed and then approved still counts.
alter table public.club_events
  add column if not exists review_reason text;

alter table public.club_events
  add constraint club_events_review_reason_check
  check (review_reason is null or review_reason in
         ('not_event', 'wrong_when', 'wrong_place', 'wrong_title', 'other'));

comment on column public.club_events.review_reason is
  'Why the admin declined an event: not_event, wrong_when (date or time), wrong_place, wrong_title, other. Null when never declined. Measure found events by submitted_by is null.';
