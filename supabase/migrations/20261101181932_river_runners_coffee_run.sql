-- St. Cloud River Runners' Sunday run by its own name (Jesse, 2026-11-01: "yes", to using the club's name and
-- details). From the club's public Google Calendar, read 2026-11-01 through Google's Calendar API: "Coffee Run",
-- every Sunday at 7:30 AM from The Local Blend (19 W Minnesota St), no Sunday skipped from Nov 1 to Dec 27;
-- "most of the group runs a 5 mile loop", others run or walk their own routes and paces, "ending around
-- 8:00-8:30am with coffee after. All paces are welcome!" The words are the agent's.

update public.clubs
set meets = '[{"what": "Coffee Run", "days": ["sun"], "weeks": null, "time": "07:30"}]'::jsonb,
    description = $about$Central Minnesota's running club since 1980, for every pace from a first 5K to ultramarathons. Its Coffee Run leaves The Local Blend in St. Joseph every Sunday at 7:30 a.m.: most of the group runs a 5-mile loop, others run or walk their own way, and everyone ends around 8 or 8:30 with coffee. On Saturdays the club meets at a different St. Cloud-area restaurant, runs, then stays for breakfast; the week's spot goes up in the club's Facebook group on Thursdays. You don't have to be a member to come along. The club also puts on the Lake Wobegon Trail Marathon each May, which finishes in St. Joseph.$about$
where entry_id = 'group-st-cloud-river-runners';
