-- A business's page in Search (BP app docs/plans/place-photos, ticket 01). Under its saved photos
-- (public.place_photos) the page shows, until the business has its own account (Jesse,
-- 2026-10-17), its About and its links. The app already reads places with select=*.
--
-- about: the place's own website description, word for word, cut at its last full sentence.
-- links: [{kind, url}], kind website, facebook or instagram, website first: what its rows open.
--
-- links is filled here once from the registry's sources (public.sources, admin only): the home of
-- each place's website (scheme and host, so an events page never stands in for the site), https
-- before http, and its Facebook and Instagram pages. Every home page was opened on 2026-10-17:
-- a place whose site is gone, taken over or broken gets no website (four failed the 2026-10-16
-- scan, BP app docs/plans/place-photos/assets/07-sites-that-failed.md; La Playette's now forwards
-- to a hosting help page, Solar Nails' certificate is broken, and Cedar Street's is Aveda's own
-- site), and a place whose site is a page of a shared host, or forwards to its new name, keeps
-- that page. Ticket 08 fills About, Facebook and Instagram for every place.

alter table public.places add column if not exists about text;
alter table public.places add column if not exists links jsonb not null default '[]';

update public.places p set links = coalesce((
  select jsonb_agg(jsonb_build_object('kind', l.kind, 'url', l.url) order by l.ord)
  from (
    select distinct on (s.kind) s.kind,
           case when s.kind <> 'website' then s.url
                else coalesce(page.url, substring(s.url from '^(https?://[^/?#]+)') || '/') end as url,
           case s.kind when 'website' then 0 when 'facebook' then 1 else 2 end as ord
    from public.sources s
    left join (values
      ('cms-autobody', 'https://cmsautobody0.wixsite.com/website'),
      ('hair-by-hanna', 'https://www.vagaro.com/hairbyhanna1'),
      ('middy', 'https://visitstcloud.com/dine/the-middy/'),
      ('golden-hour-tanning', 'https://www.goldenhourwellnessmn.com/'),
      ('home-r-w', 'https://wrhomecompany.com/'),
      ('perfect-fit', 'https://stjoewellness.com/mat-services/')
    ) page(entry_id, url) on page.entry_id = s.entry_id
    where s.entry_id = p.entry_id
      and s.status <> 'retired'
      and s.kind in ('website', 'facebook', 'instagram')
      and not (s.kind = 'website' and s.entry_id in ('328-american-legion-post', 'auto-body-2000',
               'exponential-chiropractic-healing-center', 'insurance-advisors-st-joseph', 'la-playette',
               'solar-nails-of-st-joseph', 'cedar-street-salon-spa'))
    order by s.kind, (s.url like 'https://%') desc, length(s.url)
  ) l), '[]')
where p.entry_id is not null;

-- Two Abouts as proof (Jesse, 2026-10-17), each its site's own description.
update public.places set about = 'New Orleans-inspired Southern cooking with house-made specialties, a fresh revolving menu, and a relaxed, no-rush dining atmosphere.'
  where entry_id = 'krewe';
update public.places set about = 'I am Hannah E. Remenar, aka H.E.R., and I am the proud owner and stylist at Her Hair Studio! With a deep passion for exploring the latest color and cut trends, I’ve honed my craft over nearly a decade in the industry, always putting my creativity and skills to the test.'
  where entry_id = 'her-hair-studio';
