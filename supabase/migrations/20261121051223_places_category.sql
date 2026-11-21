-- search-helpful 09 (BP app): the word a place uses for itself, under its name in Search ("Nutrition club",
-- "Hair salon", "Taxidermist"): the primary category its owner picked on Google Maps, written only when a second
-- check against the place's own site or About agreed. Null: the app keeps Google's type in a neighbour's words.
-- Jesse's yes 2026-11-19 ("use the terminology the place uses", "yes i agree"). Reads stay open as for every column.
alter table public.places
  add column category text
  constraint places_category_short check (category is null or (category = btrim(category) and category <> '' and length(category) <= 40));

comment on column public.places.category is
  'The word the place uses for itself (its Google Maps primary category, checked against its own site). Search shows it under the name.';
