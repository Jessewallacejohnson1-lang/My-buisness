-- Google's own place id for a place whose place_id is a local one (stjoe-*), found once by
-- scripts/resolve_google_place_ids.py through Locked Rule A. The app's Search asks Google
-- for a place's photos by this id (the IDs-only tier) instead of searching for the place on
-- every visit. Google's terms allow storing place ids; nothing else from Google is stored.
alter table public.places add column if not exists google_place_id text;

comment on column public.places.google_place_id is
  'Google place id for a row whose place_id is local (stjoe-*); set by scripts/resolve_google_place_ids.py through Locked Rule A. Null when nothing cleared it.';
