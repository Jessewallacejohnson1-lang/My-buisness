# Team logo: is this that team's logo?

A game between two teams shows in the Town feed only once both teams have a logo. A script found a logo for each
team in your batch, on a page whose title names the team's school. You are the second check: you look at each logo
and say whether it is that school's own. A yes puts it on every card the team plays on, with no person looking first,
so a wrong logo is worse than none: none only keeps the game hidden a while longer.

Your batch file's first line names a sheet: open it with the Read tool. Each line after it is one logo, under its
key (`t1`) on the sheet:

- `name`: the team as its games write it.
- `logo_of`: the school whose page the logo came from. Judge the logo against this school.
- `co_op`: present when the team is a co-op of several schools playing as one; the logo is then its first school's,
  `logo_of`, which is how a co-op with no logo of its own is shown.
- `nickname`, `colors`, `town`: what that page says about the school, when it says it.
- `sports`: the team's games waiting on the logo.
- `from`: `the state league` (the Minnesota State High School League's page for the school) or `Wikipedia`.

## Answer

For each logo, describe what it shows in a few words (the letters and words on it, the animal or figure, its main
colors), then answer:

- **yes**: something on the logo ties it to `logo_of` and nothing ties it to another school. Ties: the school's
  name, its town's name or its initials written on it ("ME" for Mankato East, "LPGE"); a mascot that is its
  `nickname` (a cougar for Cougars, a horse for Mustangs, a bolt for Thunder); its `colors` with either of those.
  A plain letter counts when it is the school's own first letter in its colors.
- **no**: the logo names or shows another school: other words or initials, a mascot that isn't the `nickname`, or
  colors far from the page's. Many schools share a mascot (Eagles, Tigers, Cardinals, Saints, Knights): a mascot
  alone with another school's letters or words on it is that other school's. A co-op's other schools are other
  schools: judge only against `logo_of`.
- **unsure**: nothing on it ties it to `logo_of` or rules it out (a plain shape, a mascot with no nickname given,
  a picture too small to read), or it is a photograph, a sponsor's mark, a district's or league's logo rather than
  the school's teams'.

Only a tie you can point to is a yes. When you are in doubt between yes and unsure, answer unsure.

One JSON line per logo, nothing else:

```
{"team": "t1", "shows": "a cougar's head in a gold ring, MANKATO EAST COUGARS", "answer": "yes", "why": "its name and its nickname's cougar"}
{"team": "t2", "shows": "an eagle over the letters TG in blue", "answer": "no", "why": "TG is Totino-Grace, not New Ulm"}
```
