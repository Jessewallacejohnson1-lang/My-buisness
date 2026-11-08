-- "Joetown Burger and fries at The House" is a menu post, not News (Jesse, 2026-11-08: "its a new post but
-- not news"). No copy kept.
update public.board_items set status = 'archived'
  where id = '2e0d7b16-d2cf-4066-b01e-0b0e0a2aa971';
