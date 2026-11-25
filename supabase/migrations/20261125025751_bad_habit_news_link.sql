-- News "Bad Habit Black Friday weekend" links to the wrong post (BP app event-photos 32, Progress 2026-11-24). Its facts
-- are the brewery's week schedule (DgGJMXliJnZ, posted 2026-11-23 19:35:05 UTC); its link and words are the Nov 25 early
-- opening (DgF0BMrnFzo). Both posts read 2026-11-24.
update public.board_items
set source_url = 'https://www.instagram.com/p/DgGJMXliJnZ/',
    posted_at = '2026-11-23 19:35:05+00',
    post_words = E'Thanksgiving Week is upon us - check out everything happening at Bad Habit! \n\nDrink releases, special hours, local vendor markets, and Black Friday deals. \n\n#badhabitbrewing Visit Joetown @joetownmn'
where id = '60722764-bc72-4eec-85a8-d159133661f5' and source_url = 'https://www.instagram.com/p/DgF0BMrnFzo/';
