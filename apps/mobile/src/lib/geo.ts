// Curated, building-accurate coordinates for known St. Joseph places.
// Device geocoding (expo-location) routinely drops pins on the wrong building —
// so known venues resolve here first, verified against OpenStreetMap / the
// venue's published address. Order matters: more specific venues come before
// broader areas (e.g. "Church of St. Joseph, Minnesota St" must not fall
// through to the generic downtown match).

export type Coords = { lat: number; lng: number }

const VENUES: { kw: string[]; coords: Coords }[] = [
  // — downtown storefronts —
  { kw: ['local blend'], coords: { lat: 45.56483, lng: -94.31841 } }, // 19 W Minnesota St
  { kw: ['bad habit'], coords: { lat: 45.56557, lng: -94.31863 } }, // 25 College Ave N
  { kw: ['krewe'], coords: { lat: 45.56559, lng: -94.31797 } }, // 24 College Ave N
  { kw: ['church of st. joseph', 'church of saint joseph', 'church of st joseph'], coords: { lat: 45.5647, lng: -94.3184 } }, // Minnesota St W at College Ave

  // — parks & trail —
  { kw: ['millstream'], coords: { lat: 45.57007, lng: -94.32874 } }, // Millstream Park, NW edge of town
  { kw: ['klinefelter'], coords: { lat: 45.5572, lng: -94.30304 } },
  { kw: ['memorial park'], coords: { lat: 45.56532, lng: -94.32355 } },
  { kw: ['centennial park'], coords: { lat: 45.56699, lng: -94.32363 } },
  { kw: ['northland park'], coords: { lat: 45.57285, lng: -94.31153 } },
  { kw: ['wobegon', 'trailhead'], coords: { lat: 45.56652, lng: -94.31613 } }, // trailhead park, 1st Ave NE under the water tower

  // — the campuses & monastery —
  { kw: ['sacred heart', 'chapel', 'monastery'], coords: { lat: 45.56313, lng: -94.31892 } }, // Sacred Heart Chapel dome
  { kw: ['saint john', 'st. john', 'st john', 'sju', 'abbey', 'collegeville'], coords: { lat: 45.57998, lng: -94.39229 } }, // Abbey church, Collegeville
  { kw: ['saint ben', 'st. ben', 'st ben', 'csb', 'benedict', 'gorecki'], coords: { lat: 45.55982, lng: -94.31828 } }, // CSB campus

  // — broad areas last —
  { kw: ['downtown', 'minnesota st', 'minnesota street', 'college ave'], coords: { lat: 45.5648, lng: -94.3183 } },
]

/** Exact coordinates for a known St. Joe venue, or null if we don't know it. */
export function venueCoords(location: string | null): Coords | null {
  if (!location) return null
  const t = location.toLowerCase()
  for (const v of VENUES) {
    if (v.kw.some((k) => t.includes(k))) return v.coords
  }
  return null
}
