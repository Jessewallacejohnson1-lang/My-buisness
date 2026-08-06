-- ============================================================================
-- Fixes from the Phase 5 database review.
--
-- 1. A vote could be cast on a touch that had never been served. `daily_touches`
--    is readable by any authenticated user, so the whole future bank — ids
--    included — was enumerable. Voting on an unclaimed touch pre-seeded its tally
--    before anyone saw it. For an app whose bar is "real data only, never seeded
--    counts", that is the important one.
-- 2. option_idx was only checked `>= 0`. An out-of-range vote counted toward
--    nothing (vote_counts and total_votes are both bounded) yet still set
--    `my_vote`, so the voter saw "you voted" with no row marked.
-- 3. Two concurrent compose runs could both claim the same touch, and the loser
--    silently reassigned it — one date's poll would vanish. Same shape for the
--    spotlight rotation, where both dates ended up showing the same one.
-- 4. The tally ran one correlated count per option, on every Today load, for the
--    town's single shared poll.
-- ============================================================================

-- --------------------------------------------------------------------------
-- 1 + 2. Validate votes at the write layer.
-- --------------------------------------------------------------------------

create or replace function public.validate_touch_vote()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare v_options jsonb; v_used_on date;
begin
    select options, used_on into v_options, v_used_on
    from public.daily_touches where id = new.touch_id;

    if not found then
        raise exception 'touch % does not exist', new.touch_id;
    end if;

    -- A touch that has not been served cannot be voted on. This is what stops a
    -- future poll's tally being seeded before anyone has seen it.
    if v_used_on is null then
        raise exception 'touch % has not been served yet', new.touch_id
            using errcode = 'check_violation';
    end if;

    if v_options is null or jsonb_typeof(v_options) <> 'array'
       or new.option_idx >= jsonb_array_length(v_options) then
        raise exception 'option_idx % is out of range for touch %', new.option_idx, new.touch_id
            using errcode = 'check_violation';
    end if;

    return new;
end;
$$;

drop trigger if exists touch_votes_validate on public.touch_votes;
create trigger touch_votes_validate
    before insert on public.touch_votes
    for each row execute function public.validate_touch_vote();

-- Stop handing out the unseen bank. The app never reads this table directly —
-- it goes through get_today_briefing, which is security definer — so this is a
-- pure reduction in surface.
drop policy if exists "daily touches select" on public.daily_touches;
create policy "daily touches select" on public.daily_touches
    for select to authenticated
    using (used_on is not null);

-- --------------------------------------------------------------------------
-- 3. Serialize the routine. It runs a few times a day, so taking one lock is
--    cheaper than reasoning about three separate compare-and-swaps.
-- --------------------------------------------------------------------------

create or replace function public.claim_touch(p_date date)
returns uuid
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare v_id uuid; v_pick uuid;
begin
    select id into v_id from public.daily_touches where used_on = p_date;
    if v_id is not null then return v_id; end if;

    v_pick := public.pick_touch(p_date);
    if v_pick is null then return null; end if;

    -- `used_on is null` makes this a compare-and-swap: if another run claimed
    -- this row first, we update 0 rows and fall through to re-read rather than
    -- stealing the row from the date that won.
    update public.daily_touches set used_on = p_date
    where id = v_pick and used_on is null
    returning id into v_id;

    if v_id is null then
        select id into v_id from public.daily_touches where used_on = p_date;
    end if;
    return v_id;
exception when unique_violation then
    select id into v_id from public.daily_touches where used_on = p_date;
    return v_id;
end;
$$;

-- --------------------------------------------------------------------------
-- 4. One grouped scan for the tally instead of one count per option.
--    Zeros are still emitted for unvoted options, and total_votes is still the
--    sum of exactly what the bars show.
-- --------------------------------------------------------------------------

create or replace function public.touch_tally(p_touch_id uuid)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
    with t as (
        select options from public.daily_touches where id = p_touch_id
    ),
    counted as (
        select tv.option_idx, count(*)::int as n
        from public.touch_votes tv
        where tv.touch_id = p_touch_id
        group by tv.option_idx
    ),
    aligned as (
        select idx.i, coalesce(c.n, 0) as n
        from t
        cross join lateral generate_series(
            0, greatest(jsonb_array_length(t.options) - 1, -1)
        ) as idx(i)
        left join counted c on c.option_idx = idx.i
    )
    select jsonb_build_object(
        'vote_counts', coalesce((select jsonb_agg(n order by i) from aligned), '[]'::jsonb),
        'total_votes', coalesce((select sum(n)::int from aligned), 0)
    );
$$;

revoke all on function public.validate_touch_vote() from public, anon, authenticated;
revoke all on function public.touch_tally(uuid) from public, anon, authenticated;

-- --------------------------------------------------------------------------
-- 5. Indexes: add the missing FK index, drop the one the season-aware picker
--    superseded (its predicate is a strict subset of the newer index's).
-- --------------------------------------------------------------------------

create index if not exists daily_briefings_spotlight_id_idx
    on public.daily_briefings (spotlight_id);

drop index if exists public.daily_touches_unused_idx;

-- --------------------------------------------------------------------------
-- 6. Defense in depth. RLS already blocks these writes — there are no write
--    policies — but the function grants in this schema are explicit, so the
--    table grants should be too.
-- --------------------------------------------------------------------------

revoke insert, update, delete on public.daily_briefings   from anon, authenticated;
revoke insert, update, delete on public.briefing_featured from anon, authenticated;
revoke insert, update, delete on public.daily_touches     from anon, authenticated;
revoke insert, update, delete on public.spotlights        from anon, authenticated;
revoke update, delete         on public.touch_votes       from anon, authenticated;
revoke update, delete         on public.app_events        from anon, authenticated;
