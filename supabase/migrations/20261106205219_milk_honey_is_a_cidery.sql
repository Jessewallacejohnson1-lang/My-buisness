-- Milk & Honey Ciders' page said Brewery, and it's a cidery (Jesse's yes, 2026-11-06; BP app
-- backlog 23). The app learned the type in the same commit: apply this after that reaches main.
-- `types` keeps brewery; only the line under its name and what follows from the type change.

update public.places set primary_type = 'cidery' where id = '796f4577-dd1a-49f6-aac5-49d3f8632ecb';
