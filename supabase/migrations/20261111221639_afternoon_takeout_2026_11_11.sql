-- Afternoon take-out, 2026-11-11, after the first daily weekly-list check.

-- Beer and a Bite for Heijeu Arts, today 5 PM at Beaver Island Brewing: Lacey Eidem Art's reminder post repeats
-- its own Nov 5 listing. Kept c4cda3ba ("Evening supporting Heijeu Arts", the longer About).
update public.club_events set status = 'rejected', review_reason = 'other' where id = 'e349cdc3-d28c-40a8-8c08-c529f8049b49';

-- The St. Wendel Tamarack Bog's Instagram on the list is the statewide Minnesota DNR account (minnesotadnr), so its
-- statewide tips showed as the bog's News. Archived the ones still showing: buckthorn, bears, deer-season safety and
-- the electronic licensing system.
update public.board_items set status = 'archived' where id in (
  'a4278c8f-eae7-4a7e-a21c-b5e0f3a0795f', '28d62f61-ddd8-4152-9b84-73786d08aac5',
  '2bb12a28-0af3-4cef-9d82-275ce117862f', '582bf220-c05c-4359-8227-1cdeefbe21fb');
