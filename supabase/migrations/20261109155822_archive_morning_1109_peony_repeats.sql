-- White Peony, two News that repeat what the feed already has:
-- 6030ee2d "12 Days of Giving, Nov 9-20": the same sale as the Event b4805523 "12 Days of Giving" (Nov 9 to 20), still showing. Kept: the Event.
-- d0c6b974 "Twinkle & Toast holiday collection": the sixth telling of the Nov 6-8 holiday launch (Events a85c84a6, de06234e,
-- 99ea01d6, 81eb739d; News 2015aa70, already archived). The launch is past; "in store and online now" is no news.
update public.board_items set status = 'archived'
where id in ('6030ee2d-8aea-4323-9a02-1d8580dba61f', 'd0c6b974-b810-4bde-87b0-e57808d295a4');
