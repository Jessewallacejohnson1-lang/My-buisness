-- The North Table's winter closing, twice in the feed: kept 6ccc942f "The North Table closes for the winter"
-- (Nov 9, says it's the last week), archived 551f5e02 "Closing for the Season Soon" (Nov 6, the same story before the date was set).
update public.board_items set status = 'archived'
where id = '551f5e02-698a-46d1-a0f6-c356172c2b44';
