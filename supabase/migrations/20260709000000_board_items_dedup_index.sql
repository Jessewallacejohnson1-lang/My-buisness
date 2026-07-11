-- board_items de-dup — reconstructed from MAP_BUILD_LOG.md (applied 2026-07-09).
-- A double-publish put two identical "Trivia Night" rows on the Today board; this
-- unique index makes a repeat impossible. Recurring dated rows differ by starts_at,
-- so they're still allowed. VERIFY against prod.

create unique index if not exists board_items_dedup_unique_index
    on public.board_items (
        lower(title),
        source_name,
        coalesce(starts_at, '-infinity'::timestamptz)
    );
