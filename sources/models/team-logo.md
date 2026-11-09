# Team logo: is anything against this logo being that school's?

A game between two teams shows in the Town feed only once both teams have a logo. A script found a logo for each
team in your batch on the school's own page, and checked that the page's title names the school: which school it
is, is settled. You are the second check, on the picture: is it a school's team logo, and does anything on it say it
belongs to someone else? A yes puts it on every card the team plays on with no person looking first, so a wrong logo
is worse than none: none only keeps the game hidden a while longer.

Your batch file's first line names a sheet: open it with the Read tool. Each line after it is one logo, under its
key (`t1`) on the sheet:

- `name`: the team as its games write it.
- `logo_of`: the school whose page the logo came from. Judge the logo against this school.
- `co_op`: present when the team is a co-op of several schools playing as one; the logo is then its first school's,
  `logo_of`, which is how a co-op with no logo of its own is shown.
- `nickname`, `colors`, `town`: what that page says about the school, when it says it.
- `sports`: the team's games waiting on the logo.
- `from`: where the page was found. It is settled already: leave it out of your answer.

## Answer

For each logo, describe what it shows in a few words (the letters and words on it, the animal or figure, its main
colors), then answer:

- **no**, when something on it belongs to another school:
  - words or initials naming another school or town ("TG" on New Ulm's, "MARSHALL" on Mankato East's). A co-op's
    own logo may name its member schools ("Melrose · Sauk Centre" on Fusion's): those are its own.
  - initials that aren't this school's: all of them, in order ("SF" is St. Francis, not South St. Paul, whose are
    SSP; "MBA" can be Morris-Benson Area, an A for Area). A letter alone that isn't the first letter of the school,
    its town or its nickname. A logo that is a letter, alone or dressed with flames, a bolt or a swoosh, is judged
    on its letter and its colors only, never on the `nickname`.
  - a mascot that isn't its `nickname`, when the page gives one: a tiger for the Eagles, a bear for the Bombers, an
    eagle for the Warriors, a lion for the Stars, an anchor for the Eagles. A figure fits when it is the nickname or
    its plain symbol: an anchor or a wave for Lakers, a pitchfork or a devil for Blue Devils, a bolt or a T for
    Thunder, a jackrabbit for Blackjacks, a crown or a lion for Royals, a bull for Packers, a helmet for Spartans,
    Knights or Warriors, a chief's or a brave's head for Warriors, Braves or Chiefs. Any other figure does not fit:
    a bird for Spartans, a lion for Stars, a patriot's head for Pirates, an eagle for Warriors. A copy of a professional team's logo is judged the same way.
  - its main colors plainly aren't the page's `colors`, when the page gives them: navy for maroon and white, purple
    for orange and black, red and black for green and white, green for blue and gold. Shades differ (orange for gold,
    black for navy, maroon for red, yellow for gold) and a logo may leave one of the school's colors out, but its
    biggest color must be one of them. Grey, silver, white and black fill most mascots' fur, feathers and outlines:
    judge by the colors besides them. A logo with no color but those can't be checked by its colors, so its figure
    must be plainly the nickname, not one near it: a wildcat is not a lion. Orange is not red, and purple is not blue. A nickname that names a color
    (Blue Devils, Crimson, Red Raiders) needs that color on the logo.
- **unsure**, when it is not a school's team logo at all: a photograph, a building, a sponsor's or a conference's
  or the state league's mark, or a picture too small to read.
- **unsure**, too, when the line gives neither a `nickname` nor `colors` and nothing written on the logo names
  `logo_of` (its name, its town or its initials): there is nothing to check it against. So is a logo that is only a
  letter (with flames, a bolt or a swoosh around it) when the line gives no `colors`: many schools share a letter.
  Two letters or more that are the school's initials (CC for Chaska-Chanhassen) name it, colors or not. So is a
  plain shape or crest, with no mascot, letter or words on it, unless its colors are plainly the page's; a symbol of
  the `nickname` (a comet for KoMets) is its mascot, not a plain shape.
- **yes**, in every other case: a team logo with nothing on it against `logo_of`. It need not name the school: most
  school logos are only a mascot, a letter or a crest, and many copy a professional team's. A district's mark naming
  the school's own town is the school's.

One JSON line per logo, nothing else:

```
{"team": "t1", "shows": "a cougar's head in a gold ring, MANKATO EAST COUGARS", "answer": "yes", "why": "its name and its nickname's cougar"}
{"team": "t2", "shows": "a navy B with a feather", "answer": "yes", "why": "B is Benson's first letter, the feather fits the Braves"}
{"team": "t3", "shows": "an eagle over the letters TG in blue", "answer": "no", "why": "TG is Totino-Grace, not New Ulm"}
```
