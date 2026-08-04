// places_stjoe.ts — curated real places around St. Joseph, MN for "field note" days.
// Replaces the single hardcoded Lake Wobegon Trail with a rotating set of real local
// spots. Non-commercial / outdoor / civic by design (no businesses) so a field note
// reads as a warm observation, never an advertisement. First pass — tune to taste.
//
// `name` is what gets recorded in places_mentioned (drives anti-repetition).
// `hook` is a short observational phrase the almanac editor may work in.

export interface LocalPlace {
  name: string
  hook: string
}

export const PLACES_STJOE: readonly LocalPlace[] = [
  { name: "the Lake Wobegon Trail", hook: "the crushed-limestone rail-trail that runs right through town" },
  { name: "Millstream Park", hook: "the quiet park along the Watab in town" },
  { name: "Klinefelter Park", hook: "the neighborhood park on the east side" },
  { name: "the Watab River", hook: "the little river that threads through St. Joseph" },
  { name: "the Saint John's Abbey Arboretum", hook: "the oak savanna and prairie out at Collegeville" },
  { name: "Lake Sagatagan", hook: "the lake behind Saint John's, chapel across the water" },
  { name: "Stella Maris Chapel", hook: "the little stone chapel on Lake Sagatagan" },
  { name: "the College of Saint Benedict grounds", hook: "the campus paths on the south end of town" },
  { name: "Kraemer Lake–Wildwood County Park", hook: "the county park with the boardwalk, just north" },
  { name: "Warner Lake County Park", hook: "the county park south toward Clearwater" },
  { name: "Quarry Park & Nature Preserve", hook: "the old granite quarries over in Waite Park" },
  { name: "the Sauk River", hook: "the river winding down through Stearns County" },
  { name: "the Beaver Island Trail", hook: "the paved path along the Mississippi in St. Cloud" },
  { name: "Munsinger Clemens Gardens", hook: "the riverside gardens over in St. Cloud" },
  { name: "the Rocori Trail", hook: "the rail-trail down toward Cold Spring and Rockville" },
  { name: "Two Rivers Lake", hook: "the lake northwest of town" },
]

export function localPlaceNames(): string[] {
  return PLACES_STJOE.map((p) => p.name)
}
