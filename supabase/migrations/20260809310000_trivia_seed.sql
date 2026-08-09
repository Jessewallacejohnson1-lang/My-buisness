-- ============================================================================
-- First verified St. Joseph, Minnesota trivia bank.
--
-- Facts are limited to stable civic/campus/place details already sourced from
-- official city facilities pages, campus material, and the reviewed local-place
-- datasets in this repository. Re-applying does not duplicate a prompt.
-- ============================================================================

with seed(seed_order, prompt, options, correct_idx) as (
    values
        (1,
         'Which street forms the heart of downtown St. Joseph?',
         '["Minnesota Street", "Division Street", "Broadway Avenue", "St. Germain Street"]'::jsonb,
         0),
        (2,
         'Which river runs through Millstream Park?',
         '["Sauk River", "Watab River", "Mississippi River", "Rum River"]'::jsonb,
         1),
        (3,
         'About how many acres make up Millstream Park?',
         '["12 acres", "35 acres", "68 acres", "95 acres"]'::jsonb,
         1),
        (4,
         'Which St. Joseph park has a pavilion available to rent year-round?',
         '["Cloverdale Park", "Millstream Park", "Hollow Park", "Monument Park"]'::jsonb,
         1),
        (5,
         'Which city park is the home field of the St. Joseph Saints?',
         '["Memorial Park", "Northland Park", "Centennial Park", "Rivers Bend Park"]'::jsonb,
         0),
        (6,
         'Which St. Joseph park has a foot-golf course?',
         '["Klinefelter Park", "Northland Park", "Millstream Park", "Cloverdale Park"]'::jsonb,
         1),
        (7,
         'Which park''s wetland trail crosses two pedestrian bridges?',
         '["Centennial Park", "Memorial Park", "Klinefelter Park", "Hollow Park"]'::jsonb,
         2),
        (8,
         'Which is St. Joseph''s largest city park?',
         '["Millstream Park", "Rivers Bend Park", "Northland Park", "Memorial Park"]'::jsonb,
         1),
        (9,
         'Which river borders Rivers Bend Park?',
         '["Watab River", "Sauk River", "Crow River", "Elk River"]'::jsonb,
         1),
        (10,
         'What kind of habitat covers more than 30 acres at Rivers Bend Park?',
         '["Maple forest", "Native prairie", "Cattail marsh", "Pine plantation"]'::jsonb,
         1),
        (11,
         'Which park pairs a full-size basketball court with a lighted picnic shelter?',
         '["Centennial Park", "Northland Park", "Monument Park", "Rivers Bend Park"]'::jsonb,
         0),
        (12,
         'Which pocket park is built around a historical marker from the 1940s?',
         '["Hollow Park", "Cloverdale Park", "Monument Park", "Memorial Park"]'::jsonb,
         2),
        (13,
         'What kind of trail is the Lake Wobegon Trail through St. Joseph?',
         '["A paved rail-trail", "A snowmobile-only trail", "A mountain-bike singletrack", "A boardwalk trail"]'::jsonb,
         0),
        (14,
         'The Lake Wobegon Trail is named for a fictional hometown created by whom?',
         '["Sinclair Lewis", "Garrison Keillor", "F. Scott Fitzgerald", "Laura Ingalls Wilder"]'::jsonb,
         1),
        (15,
         'Which pair of towns lies along the Lake Wobegon Trail west of St. Joseph?',
         '["Avon and Albany", "Princeton and Milaca", "Paynesville and Spicer", "Buffalo and Monticello"]'::jsonb,
         0),
        (16,
         'Where is the St. Joseph Lake Wobegon Trailhead?',
         '["610 County Road 2", "725 County Road 75", "205 Birch Street West", "1000 Dale Street East"]'::jsonb,
         0),
        (17,
         'In what year was the College of Saint Benedict founded?',
         '["1856", "1887", "1912", "1924"]'::jsonb,
         1),
        (18,
         'Which college has its campus in St. Joseph?',
         '["College of Saint Benedict", "Saint John''s University", "St. Cloud State University", "Concordia College"]'::jsonb,
         0),
        (19,
         'Which institution is the College of Saint Benedict''s academic partner?',
         '["Saint John''s University", "University of Minnesota", "Carleton College", "Macalester College"]'::jsonb,
         0),
        (20,
         'What metal gives the Sacred Heart Chapel dome its landmark finish?',
         '["Copper", "Tin", "Aluminum", "Zinc"]'::jsonb,
         0),
        (21,
         'Sacred Heart Chapel stands at the heart of which community?',
         '["Saint John''s Abbey", "Saint Benedict''s Monastery", "St. Cloud Cathedral", "Assumption Abbey"]'::jsonb,
         1),
        (22,
         'Which religious community calls Saint Benedict''s Monastery home?',
         '["Benedictine sisters", "Franciscan friars", "Dominican sisters", "Jesuit priests"]'::jsonb,
         0),
        (23,
         'Saint John''s Abbey and University are located in which nearby community?',
         '["Collegeville", "Avon", "Waite Park", "Sartell"]'::jsonb,
         0),
        (24,
         'Who designed the Saint John''s Abbey Church?',
         '["Frank Lloyd Wright", "Marcel Breuer", "I. M. Pei", "Eero Saarinen"]'::jsonb,
         1),
        (25,
         'Which lake sits behind Saint John''s and beside Stella Maris Chapel?',
         '["Lake Sagatagan", "Big Watab Lake", "Pleasant Lake", "Kraemer Lake"]'::jsonb,
         0),
        (26,
         'Which St. Joseph venue is a bakery and coffee shop?',
         '["Krewe Restaurant", "Flour & Flower", "Bad Habit Brewing", "Jupiter Moon Ice Cream"]'::jsonb,
         1),
        (27,
         'Which downtown St. Joseph business is a brewery?',
         '["The Local Blend", "Bad Habit Brewing Company", "Minnesota Street Market", "Bo Diddley''s Deli"]'::jsonb,
         1),
        (28,
         'Which downtown restaurant specializes in Cajun food?',
         '["Krewe Restaurant", "Kay''s Kitchen", "Gary''s Pizza", "The Local Blend"]'::jsonb,
         0),
        (29,
         'Which St. Joseph shop is an ice cream business?',
         '["Flour & Flower", "Jupiter Moon Ice Cream", "Minnesota Street Market", "The Local Blend"]'::jsonb,
         1),
        (30,
         'Which local business makes cider just west of town?',
         '["Milk & Honey Ciders", "Bad Habit Brewing Company", "Obbink Distilling", "The Local Blend"]'::jsonb,
         0)
)
insert into public.daily_touches (
    kind,
    prompt,
    options,
    correct_idx,
    season,
    created_at
)
select 'trivia',
       seed.prompt,
       seed.options,
       seed.correct_idx,
       'any',
       now() + (seed.seed_order * interval '1 second')
from seed
where not exists (
    select 1
    from public.daily_touches existing
    where existing.kind = 'trivia'
      and existing.prompt = seed.prompt
);

-- The publication trigger covers future briefings. If today's briefing was
-- already published before this bank arrived, claim exactly today's first row.
select public.claim_trivia((now() at time zone 'America/Chicago')::date)
where exists (
    select 1
    from public.daily_briefings
    where briefing_date = (now() at time zone 'America/Chicago')::date
      and status = 'published'
);
