-- A place's picture can be its logo (a school's crest, CSB Athletics' wordmark) when no photo of
-- it exists, and the app lays a logo out differently from a photo. A freely licensed photo
-- (Wikimedia Commons) must name its author and licence: credit holds that line. A photo from
-- the place's own website has no credit; the app shows its source_url's site.
alter table public.place_photos add column if not exists kind text not null default 'photo'
  check (kind in ('photo', 'logo'));
alter table public.place_photos add column if not exists credit text;
