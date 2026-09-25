# Design system, loading states and imagery

Read this before you touch a colour, a size, a spacing value, a font, a loading state or a
venue photograph.

## The one rule this file exists for

**Never hardcode a colour, a font size or a radius at a call site.** `[hook]` `[test]`
Colour comes from `Hue.*` (`BlockParty/Theme/BlockPartyColor.swift`), type takes a role from
`BlockPartyFont.swift` — the only file permitted to name a size — and radii come from
`BlockPartyMetrics`. `.claude/hooks/token-guard.sh` refuses the edit and
`TypographyScalingGuardTests` fails the build. **Do not add yourself to either allowlist**;
use a helper instead.

**Know where that enforcement stops.** `[prose]` Both checks read **one physical line at a
time** — the hook matches raw edit text, the test scans committed source for the literal
`.system(size:`. So a call split across lines, colour or font, is caught by **neither**:

```swift
Color(
    red: 0.1, green: 0.2, blue: 0.3
)   // invisible to both
```

Write such calls on one line if you want the guard to see them. The hook is registered only
for `Edit`/`Write`/`MultiEdit`, so a Swift file changed through `Bash` (a heredoc, `sed -i`)
is never seen at all — `TypographyScalingGuardTests` backstops the font half of that gap at
build time, and the colour half has no backstop. A human eye is the only check for either.

## Design system (`BlockParty/Theme/`) — ported from the Expo app

- **`BlockPartyColor`** (`Hue.*`) `[hook]` — six neutral tokens (`ink`, `paper`, `surface`,
  `inkSecondary`, `hairline`, `fill`) plus scoped colour:
  - **`accent`** plum/berry #8E3B6B — the one meaning-scoped accent. Live events, active
    filters, selected/saved states and primary CTAs only. Never decorative washes, never
    body copy.
  - **`statusTint`** #FDECE8 — the pin-detail status card's wash and nothing else.
  - **`heart`** #FF3040 — a liked heart and nothing else: state, not chrome. Pass it *into*
    `actionIcon(_:active:tint:)`, which sets `foregroundStyle` closer to the `Image`; an
    outer style silently loses.
  - **`brandYellowHex`** #FCE804 — the app's accent, taken from the logo's yellow field,
    with two scoped surfaces built from it: `mapWash` (68%, the Today bar's map disc) and
    `createDisc` (full strength, the tab bar's centre Create button — solid, because a
    centre button that lets the glass capsule through reads as a hole rather than an object).
  - The rule is **white ground + small yellow accents, every yellow derived from
    `brandYellowHex`** — never a second yellow, never a call-site hex. These are scoped
    surface tints, not second accents, and **two circular controls under 50pt is the agreed
    boundary**. The retired coral and `moss`/`sky`/`honey`/`clay` ramps stay deleted.
  - **What sits ON the yellow is not a free choice.** `[test]` #FCE804 has luminance 0.784,
    so white measures 1.26:1 and the dark ramp's `ink` 1.11:1 — only the light ink clears,
    at 15.0:1. Hence **`onCreateDisc`**, pinned to the light ramp. `CreateDiscContrastTests`
    pins all four numbers and pins `onCreateDiscHex` to `ink`'s light column.
  - Chrome stays predominantly ink-on-paper; photographs, cartography and weather/utility
    slabs carry their own controlled colour.
- **`BlockPartyFont`** — **text takes a role, never a raw point size.** `[hook]` `[test]`
  `Font.system(size:)` is FROZEN while `Font.custom(_:size:)` scales unbounded, and mixing
  them broke Dynamic Type across every screen. Both faces now scale against a shared text
  style. The SF helpers snap to the nearest system step, so `Font.sans(14)` renders at 15;
  Jost keeps its exact size. `Font.logo` and `Font.glyph(_:weight:)` are the deliberate
  frozen exceptions — **`glyph` is for ARTWORK only** (map markers, the heart burst, avatar
  placeholders, tab bar icons), and text reaching for it is a bug.
  - **Two faces.** Display/wordmark/headlines are **Jost** (bundled variable font, OFL
    licence alongside it); body/UI/data stay **SF Pro** via `Font.sans*`/`Font.mono*`, with
    numbers tabular via `.monospacedDigit()`.
  - **Jost's PostScript names are inconsistent upstream and must be used exactly** `[prose]`
    — `Jost-Regular`, but `JostRoman-Medium`/`-SemiBold`/`-Bold`. A wrong name falls back to
    the system font **silently**. `Font.logo` is `JostRoman-SemiBold`.
    `registerBlockPartyFonts()` registers every bundled ttf, so Jost self-registers;
    `AtkinsonHyperlegible-Bold.ttf` is still bundled but no longer referenced.
- **Brand artwork** `[prose]` — the app icon is the **wordmark lockup, black "BlockParty." on
  a yellow field**; the master is `docs/brand/source-logo-1254.png` and
  `scripts/brand/wordmark.py` regenerates every asset from it (`AppIcon`, `LaunchMark`, and
  `Wordmark`). **Two views, two meanings:** `BlockPartyMark` is the app icon, field and all,
  squircle-clipped (launch loader, invite card); `BlockPartyWordmark` is the logo on the
  app's own page, ink on nothing, and it is what the Today bar centres. Every live brand
  surface uses the exact raster. On any re-export: keep the icon **full-bleed** (no alpha;
  iOS applies its own mask), regenerate all three assets plus the waitlist site's favicons
  from the same master, and re-measure both `BlockPartyMark.contentFraction` and
  `BlockPartyWordmark.aspect` — the script prints both.
- **`BlockPartyMetrics`** — four radii `[prose]`: `button` 12 (a rounded square, **never a
  pill**, with exactly one recorded exception — `PinDetailSheet`'s floating action bar is a
  Flighty-faithful capsule behind the `actionBarShape` constant, per `DECISIONS.md` §6, so
  do not "fix" it), `tile` 16, `card` 20, and `bento` 22, deliberately outside the 12/16/20
  scale for large gradient slabs. `bento` and `Motion.bentoExpand`/`tilePress` have one
  consumer left after the strip-down; **keep them** — they are the spec the parked tiles are
  rebuilt against. Plus one neutral `CardShadow` (black @ 6%) and the map shadows
  (`mapFloatShadow`, `mapSheetShadow`).

**Raw colour is centralized by role, not banned outright.** `[prose]` Beyond
`BlockPartyColor`: `BasemapPalette.swift` (sage parks, blue water), `WeatherBackground.swift`
and the utility gradient definitions. Logo fallback art and the garbage-truck illustration
are content-specific exceptions. **Do not make the basemap grayscale** — that experiment
failed because the river and parks disappeared into the land. `SpotCategory.tint`,
`PlaceFamily.tint` and `EventCategory.tint` all resolve to `Hue.ink`: category is carried by
the glyph, while live/active/selected state may use `Hue.accent`.

## Strategy playbook — `docs/playbook.md`

**Read `docs/playbook.md` ("Steal This") before design or launch-strategy work.** `[prose]`
Partiful is the north-star model (quiet action hierarchy, photography-forward content,
SMS-first not push-first); Front Porch Forum and Nextdoor set the community mechanics
(verified real-name signup, per-town go-live thresholds, seed content *before* users arrive,
no raw social feed). It is a dated document and parts of it are superseded — live Theme code
and `DECISIONS.md` win wherever they disagree.

## Loading, spinners and imagery

- **Loading is a skeleton, never a spinner, never a blank screen, and never a full-screen
  cover.** `[test]` Any surface waiting on a fetch renders placeholder shapes the size and
  position of the content that is coming, so the real data resolves *in place* with no
  layout jump. **The system already exists — do not write a new one:** `SkeletonBlock` /
  `SkeletonLine` / `SkeletonCircle` plus `.shimmering()` in
  `Features/Components/Skeleton.swift` (one masked light sweep for the whole group, GPU-only,
  phase-driven off the wall clock so every skeleton on screen sweeps in lockstep; Reduce
  Motion degrades it to a slow opacity breath), and the wrappers `FeedSkeletonSection` /
  `FeedSkeletonStrip` in `FeedStateViews.swift`. `BriefingSkeletons.swift` is written but not
  yet mounted — whoever ships the first briefing module mounts it; it is not dead code. **`LoadingGuardTests` enforces this at the
  source level; if it fails, build a skeleton rather than adding yourself to its allowlist.**
  The rules:
  - Match the real layout closely enough that swap-in doesn't move anything.
  - A heading known before the fetch renders for REAL — only the unknown shapes stand in.
  - Cross-fade the hand-off keyed on the load flag (`.animation(Motion.smooth, value:
    model.loaded)` with `.transition(.opacity)` on both branches).
  - Mark placeholder shapes `.accessibilityHidden(true)`, or give the group one
    `.accessibilityLabel("Loading …")`.
  - **Don't flash** — if the data is already cached, render it directly rather than showing a
    skeleton for one frame.
- **`ProgressView` has exactly one legitimate use: an action already tapped, in flight,
  inside the control that started it.** `[test]` `LoginView`, `AddFormView`,
  `EditProfileView` and `InlineAction` are the entire allowlist in `LoadingGuardTests` —
  there is no content shape to stand in for there. Content — a screen, a list, a card, a feed
  section, an image well — never gets a spinner.
- **There is no full-screen loading cover, and no tab-readiness plumbing.** `[prose]` It was
  deleted on 2026-09-21 because it had begun covering content that was already on screen: a
  slow network dropped a dark screen over a finished one. **A tab still fetching shows its
  own skeleton, for as long as it takes.** Do not reintroduce a readiness gate.
- **Imagery comes from the Google Places Photo API at runtime — that is the default, not a
  fallback.** `[prose]` Photography is the main colour-bearing venue content layer, and
  hand-curating it does not scale. Resolve it live through **`VenuePhoto`**, backed by
  `GooglePlacesService.confidentPhoto(name:coordinate:)` or `confidentPhoto(forFreeText:hint:)`.
  Do **not** reach for a bundled image because a photo is missing — first check whether the
  venue resolves.
  - **Locked Rule A is the trust gate, not a formality.** `[prose]` A photo is shown only
    when Google's text-search match clears a **name-aligned, tiered radius** around the
    curated coordinate: **90 m** when the names merely align, **400 m** on an exact name,
    **2 km** on an exact name AND a large-footprint type (park · arboretum · trail · campus,
    where a centroid pin legitimately sits far from our curated door). The radii are
    **measured, not guessed** (39 live lookups; the `RuleA` enum's docs in
    `GooglePlacesService` carry the working) — a flat 75 m used to reject 6 of 7 real venues. `search()`
    alone is a fuzzy match and **must never source a photo**.
  - **The API supplies the photo; a person still spot-checks how it looks.** `[prose]`
    Within a cleared place, `bestScenicPhoto` picks by geometry only — it cannot tell a vista
    from a highway sign, a trash barrel, or a portrait shot that crops to an ugly middle
    band. `scripts/review_park_photos.py` assembles a contact sheet for exactly that review.
  - **ToS, and they shape the architecture** `[prose]`: `place_id` **may** be persisted —
    store it in Supabase and key off it. Photo **names may NOT be persisted** — they live
    only in the in-memory session cache and must be re-fetched from a fresh `details()` call,
    so never write one into a DB column or an `image_url`. Any `authorAttributions` **must be
    displayed wherever the image appears**. Keep the `X-Goog-FieldMask` minimal — the fields
    you request *are* the cost.
  - **Bundling a local image is the narrow exception** `[prose]`, for a place Google
    genuinely can't serve or where the auto-pick stays bad: a hand-picked landscape in
    `Resources/Images` plus a `KnownLocalPhoto` entry, sourced from city or owner-supplied
    material (never a Google photo), recording the source and any permission caveat in the
    code comment.
- **Map-pin logos are an OFFLINE pipeline, not runtime** `[prose]` — contrast the live photo
  path above. The brand logo on a POI pin comes from `places.logo_url` (the Supabase
  `place-logos` Storage bucket); a pin with none falls back to its category glyph.
  Regenerate in three steps: **`fetch_place_logos.py`** resolves each `places` row's website
  (Google Places details for real `ChIJ*` ids, text search for the synthetic local ones — it
  expects the `stjoe-*` prefix, which is what production carries) and walks a favicon ladder (apple-touch-icon → `og:image` → `<link rel=icon>` →
  `/favicon.ico` → Google favicon service), normalizing to a 256×256 PNG;
  **`logo_montage.py`** tiles them with the 26px pin-crop preview for a human approval pass;
  **`upload_place_logos.py`** pushes approved PNGs to the bucket and prints the
  `places.logo_url` SQL (needs a scoped insert policy, or `SUPABASE_SERVICE_ROLE_KEY` to
  bypass RLS).
