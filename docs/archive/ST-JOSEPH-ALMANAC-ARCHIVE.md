# St. Joseph almanac archive

Rescued on 2026-09-25, immediately before the almanac was removed from the app and its
tables were dropped from Supabase. **This file is the only surviving copy.** It is content,
not code — nothing reads it, and nothing is supposed to.

Two things are worth keeping here: the town facts, which are real local research, and the
generated lines, which are the clearest record of the voice the almanac was written in.

## Town facts

Fifteen distinct facts, from 53 daily rows in `daily_briefings.almanac_md` between
2026-08-05 and 2026-09-26 (most repeated on a rotation). Usable for onboarding copy, a
"did you know" line, launch posts, or seeding a future feature. **Verify any date before
publishing it** — these were generated, and were never fact-checked against a source.

- St. Joseph was first settled in 1854, a German farming community answering Father Francis Pierz's call to central Minnesota.
- The village was originally called Clinton and took the name St. Joseph, after its early log chapel's patron saint, around 1870.
- St. Joseph was incorporated as a village in 1890.
- St. Joseph sits in Stearns County just west of St. Cloud, part of the wider metro but a town all its own.
- The stone Church of St. Joseph, built in 1869, is the oldest church in Stearns County — fieldstone below, granite brick above.
- Sacred Heart Chapel opened in 1914, and its ribbed dome rises about 135 feet — the tallest thing in town.
- Saint Benedict's Monastery traces to 1857, when Benedictine sisters came west and settled in St. Joseph by 1863.
- The College of Saint Benedict opened in St. Joseph in 1913 with just six students.
- A few miles west in Collegeville, Saint John's University was founded in 1857 by Benedictine monks from Bavaria.
- Saint John's Abbey Arboretum wraps the Collegeville campus in more than 2,500 acres of prairie, oak savanna, woods and lakes.
- The paved Lake Wobegon Trail begins in St. Joseph and runs west along an old railroad line through Avon and Albany.
- The Lake Wobegon Trail is named for the fictional town Garrison Keillor set in this corner of Minnesota.
- The Millstream Arts Festival fills downtown with a juried art show on the last Sunday of August each year.
- Joetown Rocks, the parish festival around the Fourth of July, has been a St. Joe tradition for over a hundred years.
- The St. Joseph Meat Market has made fresh meats and homemade sausage in town for more than a century, family-run to this day.

Three more lines were day-filler rather than facts, kept for tone:

- *Early August, and the evenings pull back a little earlier each night.*
- *Thursday, and the bins go out tonight.*
- *Saturday, with nothing on the calendar. That is its own kind of plan.*

## The generated voice

Thirteen personalized lines from `almanac_daily`, 2026-07-21 to 2026-08-06, written by the
`daily-almanac` edge function. The label is the format the generator chose. These are the
best reference for how the almanac was meant to sound — observational, specific to a real
place, never cheerful at the reader.

**`field_note`** — The Watab River is running clear under a first-quarter moon tonight. With the sun not setting until **8:58**, there's plenty of time to walk the little river that threads through St. Joseph and watch how the light sits on the water before dark.

**`almanac_fact`** — The moon is at first quarter tonight, halfway lit and climbing toward full. Days are slipping back now—**13 minutes** shorter than a week ago, the year's arc bending toward August.

**`field_note`** — The first quarter moon sits halfway lit in a clear sky tonight. Two Rivers Lake, the lake northwest of town, will hold that light on its surface well after sunset at **8:57**. Worth a look if you're heading that way before dark.

**`countdown`** — St. Joseph Farmers Market is tomorrow at **3 PM** on Friday. It's been two weeks since you were last there—time to circle back.

**`almanac_fact`** — The moon is waxing gibbous now, **80 percent** lit and fattening toward full. Days are still slipping back—**13 minutes** shorter than a week ago. Summer's turn is coming.

**`callback`** — The Farmers Market at Lake Wobegon Trailhead runs again tomorrow—you were there **2 days** ago. Overcast and **97°**, but the market keeps its rhythm. Worth the trip back.

**`field_note`** — Klinefelter Park sits clear and open tonight—the full moon at **99 percent** lit will fill the whole east side in white. High of **92** today means the grass will still hold warmth well after sunset at **8:50**.

**`nudge`** — Overcast Friday with a high of **75**—soft light and no pressure to do much. Days are sliding back now, **17 minutes** shorter than a week ago. If you step out before the waning gibbous rises tonight, the evening will hold the warmth.

**`almanac_fact`** — Days are drawing in now—**17 minutes** shorter than a week ago. The waning gibbous hangs at **89 percent** lit, past its peak and thinning toward dark. Summer's grip is loosening, though the clear sky and **84°** high will hold the warmth through Saturday.

**`field_note`** — The Stearns County Fair closes today over in Sauk Centre—last chance if you haven't made the drive. Partly cloudy and **84°**, decent traveling weather. Millstream Park sits quiet along the Watab if you'd rather stay in town; the water moves slower in August heat.

**`almanac_fact`** — The moon is in its last quarter now, **60 percent** lit and heading toward dark. Days have shortened by **18 minutes** since a week ago—summer's slow turn toward fall is underway, though the warmth isn't gone yet.

**`nudge`** — Clear skies and **79°** high on a Wednesday—nothing demanding, just decent light and air. Days are still shortening, **17 minutes** less than a week ago, so the evenings stretch a little longer now. Step out if the mood takes you.

**`field_note`** — Two Rivers Lake sits northwest of town, still and open in the overcast. Days are **18 minutes** shorter than a week ago now—August is thinning toward fall, though the air stays warm. The lake holds that quiet that comes before the season turns.
