# Place logo: which of these files is this place's own logo?

Each place in your batch is a business or group in the app with no logo yet. A script read its website and saved the
pictures that page marks as a logo, an icon or its share picture. You pick the one that is the place's **own** logo,
or none. Your pick goes on the place's Search tile, its map pin and its Event cards with no person looking first. A
second reader picks on their own, and a logo goes live only when both pick the same file. A wrong logo is worse than
none: none only leaves the place on its plain tile until a later look.

The batch file's first line names a sheet: open it with the Read tool. Each line after it is one place, its row on the
sheet under its key (`p1`), its files numbered left to right with their size in px:

- `name`: the place as the app shows it. Judge every file against this name.
- `kind`: what the place is, when known.
- `website`: where the files came from. The site may belong to someone else: a parent company, a landlord, a
  builder, a directory.
- `files`: each file's number and the address it came from; the file name is often a clue (`logo`, `favicon`).

## Steps

1. For each file of a place, note in a few words what it shows: the words on it, its mark, its main colours.
2. Pick the place's **own** logo:
   - it names the place (its name, its initials, the words of its name), or
   - it is the brand mark the place's own site uses, on a site whose name is the place's, or
   - the place is one location of a chain or franchise under that brand's name ("Caribou Coffee", "Holiday"), and the
     file is that brand's logo.
   When the same logo comes more than once, pick the one with the most px.
3. Answer `null` when no file is its **own** logo. A file is not its own logo when it is:
   - another name's logo: a parent company, an owner, a manager or landlord, a builder (an apartment page showing its
     developer's logo), even on the place's page;
   - a badge: a member association, an award, a certification, a sponsor, a supplier or partner, a payment or social
     network's icon;
   - a photograph or a screenshot: a building, a product, a person, a truck, a statue, the site's own page;
   - a site builder's or theme's stock icon, or a picture too blurred to read;
   - a logo drawn only in white, made for a dark header: it vanishes on the app's light tile.
4. For a pick, say whether white inside the logo belongs to it (`white_inside`): `true` when the logo draws white
   shapes inside its own outline (white letters on a coloured badge, a badge's white middle); `false` when its white
   is only the page around it and the holes of its letters.

You are done when every place in the batch has its line.

## Answer

One JSON line per place, nothing else:

```
{"place": "p1", "logo": 2, "white_inside": false, "why": "red script 'Kay's Kitchen', its name; 1 is a photo of a plate"}
{"place": "p2", "logo": null, "why": "1 and 2 are TCC Materials' mark, its parent company's name, not Amcon's"}
```

`why` names what you saw: the words or mark that make it the place's own, or whose it is instead.
