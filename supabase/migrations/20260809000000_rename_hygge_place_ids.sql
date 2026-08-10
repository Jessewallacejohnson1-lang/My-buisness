-- ============================================================================
-- Remove the retired Hygge brand from synthetic St. Joseph place identifiers.
--
-- The 62 locally researched/curated places use synthetic `hygge-stjoe-*` IDs;
-- the other 29 places use real Google `ChIJ*` IDs and must remain unchanged.
-- Rename only the old synthetic prefix and align its provenance tags with Block
-- Party. The old-prefix predicate makes the data rewrite idempotent.
--
-- `place_id` is unique, so abort before updating if a proposed `stjoe-*` ID is
-- already owned by another row. Place-logo objects are keyed by `places.id`
-- UUID, not `place_id`, so their `logo_url` values do not need to change.
-- ============================================================================

do $migration$
declare
    v_collision text;
begin
    select existing.place_id
    into v_collision
    from public.places as old
    join public.places as existing
      on existing.place_id = regexp_replace(
          old.place_id,
          '^hygge-stjoe-',
          'stjoe-'
      )
     and existing.id <> old.id
    where old.place_id like 'hygge-stjoe-%'
    limit 1;

    if v_collision is not null then
        raise exception
            'cannot rename Hygge place IDs: target place_id % already exists',
            v_collision
            using errcode = 'unique_violation';
    end if;

    update public.places
    set place_id = regexp_replace(place_id, '^hygge-stjoe-', 'stjoe-'),
        source = case source
            when 'hygge_research' then 'bp_research'
            when 'hygge_curated' then 'bp_curated'
            else source
        end
    where place_id like 'hygge-stjoe-%';
end
$migration$;
