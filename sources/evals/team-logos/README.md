# Team logo eval

`right.json`: the logos Jesse approved on 2026-11-05 (BP app `references/game-card/logos/teams-2026-11-05.json` and
`-05b.json`), each team written as `team_logos.py` writes it for the helper: the state league's page when its lookup
agrees with the approved logo (own or a co-op's first school), else the approval's own notes. Its `logo_url` is the
live file, saved once under a name that never changes.

Left out: Southwest Christian. Its games are at Southwest Christian High School (Chaska, the Stars); the approved
logo is Southwest Minnesota Christian's (Edgerton, the Eagles), another school. Crookston, Proctor and Anoka-Hennepin: their approved
logos are their districts' marks ("Crookston Public Schools, ISD 593", "Proctor Public Schools", the Anoka-Hennepin
district's emblem), which Jesse ruled out on
2026-11-09: a logo must be one school's, never a town's or a district's. North-Tartan uses the approval's
notes: the league lookup found Lakeville North for it, which check 1 now refuses.

Run `python3 sources/scripts/check_team_logos.py`.
