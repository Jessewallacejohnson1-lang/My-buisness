-- The Church of Saint Joseph's About (BP app place-pages 06; source-registry skill, "A new place in
-- the app: its profile first"). The place came in on 2026-11-16 with no About: its website is a page
-- of the shared Benedictine Catholic Communities site, and place_rows.py read no description from it.
-- Written from its own page and header logo, its festival page and the St. Joseph Newsleaders
-- (2019-07-12), and passed by two separate agent checks (Jesse's rule for a new place, 2026-11-17).
-- Its links stay.

update public.places set about = $about$The Church of Saint Joseph is a Catholic, Benedictine parish on West Minnesota Street in St. Joseph. Together with Saint John the Baptist, it makes up the Benedictine Catholic Communities of Saint Joseph & Saint John the Baptist. Parish volunteers took apart the church's old interior for its 2019 renovation, which ended with a Rededication Mass. Each July 3 and 4, its Joetown Rocks festival brings food booths, a concert, bingo, a quilt auction and fireworks.$about$ where entry_id = 'church-jospehs-st' and about is null;
