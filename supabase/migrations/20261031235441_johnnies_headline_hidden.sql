-- Tonight's social watch wrote "Johnnies win MIAC cross country title" (College of Saint Benedict's
-- Instagram), but its own blurb says Cole Stencel won the individual title and the Johnnies finished
-- third. The headline claims a team title they didn't win, so it's taken out of the Town feed.
-- A repeat mention keeps it archived (apply_judged only lifts a staging item).
update public.board_items set status = 'archived'
 where id = '9bc8a073-1409-4d83-ad17-da2dd9f401a5';
