-- Instagram links for four places, found by the 2026-10-22 Apify Google Maps pass (ADR-020,
-- amended 2026-10-22). Each link was on the place's own website, and the Google listing it
-- came from matched the census by phone, street or website. Jesse's yes: "Yes, add the 4
-- Instagram links to the app." Appended after the website and Facebook links, so the website
-- stays first; a place that already has an Instagram link is left alone.

update public.places p
set links = coalesce(p.links, '[]'::jsonb) || jsonb_build_array(jsonb_build_object('kind', 'instagram', 'url', v.url))
from (values
  ('2b90146d-3652-4a02-b1a5-a5d132c62522'::uuid, 'https://www.instagram.com/blushsalonmn'),
  ('cf3c7388-f4ab-4522-ae1d-3d2a018c69a5'::uuid, 'https://www.instagram.com/centralmnagent'),
  ('b21d44d8-e28f-4b4e-8a7d-65eed035eb31'::uuid, 'https://www.instagram.com/kensington_bank'),
  ('e70d7fad-c801-48f5-b874-2191defaf9b5'::uuid, 'https://www.instagram.com/kpoweryogamn')
) as v(id, url)
where p.id = v.id
  and not coalesce(p.links, '[]'::jsonb) @> '[{"kind": "instagram"}]'::jsonb;
