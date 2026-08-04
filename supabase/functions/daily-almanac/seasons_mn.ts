// seasons_mn.ts — hand-curated Minnesota / St. Joseph seasonal markers.
// The almanac editor may mention a marker that is "in season" for today's date.
// Windows are inclusive [start, end] in local month/day; a window may wrap the year.
//
// Civic-event windows are set from verified 2026 dates (sources below); note the ones
// that float year to year and drift a few days:
//   - Stearns County Fair (Sauk Centre): Jul 29–Aug 2, 2026.
//   - Millstream Arts Festival (downtown St. Joseph): last Sunday of AUGUST — Aug 30, 2026.
//   - MN State Fair: 12 days ENDING Labor Day — Aug 27–Sep 7, 2026.
//   - MEA / Education MN conference: 3rd Thursday of October — Oct 15, 2026 (schools out Thu–Sun).
//   - Firearms deer opener: Saturday nearest Nov 7 — Nov 7, 2026.
// The natural markers (ice-out, first 80°, frost, leaf color, snow, solstices, sap run)
// are central-MN seasonal norms and are inherently approximate.
// Sources: mnstatefair.org, stearnscountyfair.com, millstreamartsfestival.org,
// educationminnesota.org, MN DNR firearms deer season.

export interface SeasonMarker {
  key: string
  /** A short, factual phrase the almanac may work in — no hype, no imperative. */
  label: string
  start: { month: number; day: number }
  end: { month: number; day: number }
}

export const SEASON_MARKERS_MN: readonly SeasonMarker[] = [
  { key: "deep_winter",      label: "the deep-cold stretch of winter",              start: { month: 1,  day: 5 },  end: { month: 2,  day: 5 } },
  { key: "sap_run",          label: "maple sap starting to run",                    start: { month: 2,  day: 25 }, end: { month: 3,  day: 25 } },
  { key: "ice_out_watch",    label: "ice-out watch on the lakes",                   start: { month: 3,  day: 25 }, end: { month: 4,  day: 20 } },
  { key: "spring_migration", label: "loons and geese back on the water",            start: { month: 4,  day: 10 }, end: { month: 5,  day: 5 } },
  { key: "first_80",         label: "the first real 80° day of the year",           start: { month: 5,  day: 10 }, end: { month: 6,  day: 5 } },
  { key: "summer_solstice",  label: "the longest days of the year",                 start: { month: 6,  day: 18 }, end: { month: 6,  day: 23 } },
  { key: "fourth_of_july",   label: "the Fourth of July on the lake",               start: { month: 6,  day: 28 }, end: { month: 7,  day: 6 } },
  { key: "county_fair",      label: "the Stearns County Fair over in Sauk Centre",  start: { month: 7,  day: 27 }, end: { month: 8,  day: 3 } },
  { key: "millstream_arts",  label: "the Millstream Arts Festival in downtown St. Joseph", start: { month: 8, day: 26 }, end: { month: 8, day: 31 } },
  { key: "state_fair",       label: "the Great Minnesota Get-Together (State Fair)", start: { month: 8,  day: 27 }, end: { month: 9,  day: 7 } },
  { key: "first_frost",      label: "first-frost watch",                            start: { month: 9,  day: 18 }, end: { month: 10, day: 10 } },
  { key: "leaf_peak",        label: "peak fall color in central Minnesota",         start: { month: 9,  day: 28 }, end: { month: 10, day: 12 } },
  { key: "mea_weekend",      label: "MEA weekend (the fall school break)",          start: { month: 10, day: 15 }, end: { month: 10, day: 18 } },
  { key: "first_snow",       label: "first-snow watch",                             start: { month: 10, day: 25 }, end: { month: 11, day: 20 } },
  { key: "deer_opener",      label: "the firearms deer opener",                     start: { month: 11, day: 7 },  end: { month: 11, day: 15 } },
  { key: "lakes_freeze",     label: "the lakes starting to lock up with ice",       start: { month: 11, day: 25 }, end: { month: 12, day: 20 } },
  { key: "winter_solstice",  label: "the shortest day of the year",                 start: { month: 12, day: 19 }, end: { month: 12, day: 23 } },
]

/** Markers whose inclusive window contains (month, day). Handles year-wrapping windows. */
export function seasonMarkersFor(month: number, day: number): SeasonMarker[] {
  const asNum = (mo: number, d: number) => mo * 100 + d
  const today = asNum(month, day)
  return SEASON_MARKERS_MN.filter((mk) => {
    const s = asNum(mk.start.month, mk.start.day)
    const e = asNum(mk.end.month, mk.end.day)
    return s <= e ? today >= s && today <= e : today >= s || today <= e
  })
}
