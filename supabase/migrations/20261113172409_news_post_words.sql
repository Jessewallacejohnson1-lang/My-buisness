-- A News keeps its post's own words (BP app docs/plans/town-feed, ticket 65). Jesse, 2026-11-13: "can we copy their
-- description and be able to click card and read more". The headline and blurb stay Block Party's words for the card;
-- post_words is the caption as the place posted it, which the News page shows in full.
--
-- The social watch fills it after each save (morning.py save_words, only for a post that is the place's own and has
-- its own link); the phone reads it by id, as it reads any published News (policy "read published items").
-- Nothing else changes: get_town_feed and apply_judged don't carry it.

alter table public.board_items add column post_words text
  -- Facebook's captions run longest; a week of reads topped out at 2,998 characters.
  constraint board_items_post_words_length check (char_length(post_words) <= 10000);

comment on column public.board_items.post_words is
  'The post''s own words, as the place wrote them (town-feed 65); null for a website story or a post not its own.';
