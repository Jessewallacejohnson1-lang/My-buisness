# towns/

One file per town. The offline scripts read the town they are working on from
here, so adding a town is one new `towns/<slug>.json` and no script edits.

```bash
python3 scripts/review_park_photos.py                    # St. Joseph (the default)
BP_TOWN=st-cloud python3 scripts/review_park_photos.py   # another town's file
```

`scripts/town.py` loads the file and stops with a plain message if it is missing
or lacks a field.

## Fields

| Field | Used by | What |
| --- | --- | --- |
| `slug` | all | Must match the file name. |
| `short_name` | `rank_rain_roster.py` | Written into the generated `TownRainRoster.swift` header. |
| `search_suffix` | `fetch_place_logos.py`, `review_park_photos.py` | Appended to a place's name for Google text search ("Millstream Park St. Joseph MN"). |
| `center` | `review_park_photos.py` | `lat`/`lon` the park search is biased around. |
| `search_radius_m` | `review_park_photos.py` | Radius of that bias circle, metres. |
| `place_id_prefix` | `fetch_place_logos.py` | Prefix of the town's hand-made `places.place_id` rows (real Google rows start `ChIJ`). |
| `parks_file` | `review_park_photos.py` | Swift file listing the town's parks (`title:` / `lat:` / `lon:`). |
| `rain_excluded` | `rank_rain_roster.py` | Businesses whose logos must not fall in town rain, each with a reason. Grouped; the group names are for people, the script reads every group. |

## Not in here yet

The scripts are the only readers so far. These still carry St. Joseph on their own
and are the next steps toward a second town:

- **The app** — `BlockParty/Models/Town.swift` (name, centre, time zone), plus the
  curated data in `Features/Map/MapSpots.swift`, `Backend/KnownVenues.swift` and
  `Backend/CityParks.swift`.
- **The almanac edge function** — `supabase/functions/daily-almanac/` (`weather.ts`
  and `index.ts` coordinates and time zone, `places_stjoe.ts`, `seasons_mn.ts`).
- **The `places` table** has no town column, so `fetch_place_logos.py` still walks
  every row regardless of `BP_TOWN`.
