# Feed Pattern Brief — Today → Social Feed

Phase 0 research for the Today-tab social feed. Source: **Mobbin MCP** (real iOS
screens, cited per row). One recommendation per pattern, concrete values, filtered
through `block-party-brand` (monochrome ink-on-paper, no accent yet, no raw hex).

**Read this with the spec open.** Where the spec and the references agree, I just
confirm the spec value. Where they diverge, the recommendation says so, and the
open ones are collected under **Decisions for the gate** at the bottom.

## References pulled

| App | What it anchors | Representative screen |
|---|---|---|
| Instagram | Action-row order, inline counts, double-tap like | [feed post + counts](https://mobbin.com/screens/0aad3a45-6001-47da-8d48-82b926bb8102) · [classic row](https://mobbin.com/screens/c1bd6c92-b975-4b68-a024-31500168e4cb) |
| komoot | Photo card + facepile/comment social row | [480 liked / 6 comments](https://mobbin.com/screens/405f0730-04fa-4acf-a7de-9205fe3a14d1) · [Like/Comment row](https://mobbin.com/screens/28b72d5e-851b-4c65-b09f-35484e04ceb5) |
| Cosmos | Minimal monochrome feed density, floating chrome | [Featured masonry](https://mobbin.com/screens/b19131b4-609e-45ab-8c3e-c3c44219103b) |
| Partiful | Going/RSVP delight (palette rejected) | [Going / Maybe / Can't Go](https://mobbin.com/screens/301b1252-7ce0-4a4a-b2ab-8263ed634515) |
| Strava | Kudos summary line above a separate action bar | [You + 174 others gave kudos](https://mobbin.com/screens/e965959f-df71-4d0b-b83f-a848b371d9f7) |
| Airbnb | Card restraint — no box, chip top-left, save on image | [listing card](https://mobbin.com/screens/d445dedc-9cd0-4b7d-a027-e5c5f324b31a) |

## Pattern recommendations

| Pattern | Reference evidence | Recommendation (concrete) |
|---|---|---|
| **Card / restraint** | Airbnb + Cosmos: image is the card, no box/shadow, whitespace between, chip on image | **Keep spec.** 16pt side margins, 28pt vertical gap, 5:4, radius `20` continuous (= brand Cards token). No border, no shadow, no container fill. |
| **Date chip** | Airbnb "Guest favorite" = material capsule, top-left inset | Material chip top-left, `FRI JUL 24` 11pt semibold uppercase, tracking 0.8. **Brand override: radius `12` rounded-square, not a Capsule** (brand bans pills). `.ultraThinMaterial`. |
| **Title / meta** | Airbnb, komoot, Strava all put title *below* the image; IG overlays nothing | **Keep spec's overlaid title** (bottom-left, 22pt bold white, scrim) — it is more image-forward and frees the below-image zone for social. Divergence from refs is intentional; flagged as Decision 2. |
| **Scrim** | IG/komoot use bottom gradients on photos only | Linear black 0%→55%, bottom 40% of image. Photos only — never on the typographic fallback. |
| **Action row order** | Instagram canonical: heart · comment · share (left), bookmark (right) | **Keep spec exactly.** Icons 22pt, 1.75pt stroke, 24pt gaps, bookmark pinned right. Rest = `ink` @ 45%; active = `ink` fill (not IG red — monochrome). |
| **Like count placement** | IG-new shows count inline by the heart; komoot/Strava use a summary line above the row | **Resolve the spec's double-count:** likes live **only** on the action-row heart, inline, `.contentTransition(.numericText())`. The social meta line carries the **going facepile only** — drop the `· 12 likes` suffix there. (Decision 3.) |
| **Facepile** | komoot "480 liked this" + overlapping avatars bottom-left; Strava "You and 174 others" | **Keep spec.** 24pt avatars, 8pt overlap, max 3, `Sam and 3 others are going` in `inkSecondary`. Add a 1.5pt `paper` separator ring between avatars for legibility. |
| **Like animation** | IG double-tap = big white heart burst, center | **Keep spec.** Tap: 1.0→1.3→1.0 `spring(0.3, 0.5)`, fills on upswing. Double-tap: white heart 0→1.15→1.0 `spring(0.3, 0.55)`, hold 500ms, fade 200ms. |
| **Save** | Airbnb heart top-right on image; bookmark is standard | **Keep spec.** Bookmark translates down 4pt + fills, returns `spring(0.35, 0.7)`. |
| **Join / going button** | Partiful delight, but gradient bubbles + emoji = far too colorful for us | **Reject Partiful's palette.** 44pt **rounded-square** (radius 12) `ink` "+" → checkmark morph + **square** ring-stroke burst + success haptic (Decision 1 → square, on-brand). Borrow only the *count* idea → surface going count in the facepile line. |
| **Count animation** | Partiful shows a live "1 Going" capsule | Going count rolls up via `.numericText()`; new avatar pops into facepile scale 0→1.0 `spring(0.35, 0.6)`. |
| **Empty state** | Strava "Be the first to give kudos!" — inline, no box | **Keep spec.** One quiet inline row, 15pt `inkSecondary`: `Nothing planned today` + 28pt ghost "+". No card. On-voice: also OK → "Nobody's planned anything today." |
| **Section labels** | Cosmos/Airbnb: near-zero section chrome | **Keep spec.** Micro-labels only, 11pt semibold uppercase `ink` @ 35%, tracking 1.0, 32pt top pad: `TODAY` / `THIS WEEK` / `LATER`. Kill the H2s and the boxed empty card. |
| **Pull-to-refresh** | Refs use default UIKit; brand wants a block moment | **Keep spec** (brand-driven, no ref needed). Rotating-square block-motif spinner, 1s period. Reduce Motion → static square + system refresh semantics. |
| **Skeletons** | — | Image-shaped radius-20 blocks at `fill`, shimmer opacity 0.5→1.0→0.5, 1.2s loop, max 3. |

## Brand reconciliations (apply everywhere, not optional)

1. **No raw hex.** Every `#0A0A0A` in the spec → `Hue.ink` (the token is `#111111`).
   `#F4F4EF` → `Hue.paper`. Add a token before inlining anything.
2. **On-paper grays → tokens.** Spec's 60%/45%/35%-black on paper → `Hue.inkSecondary`
   (or `ink.opacity` on the exact ladder); 12%-black hairline → `Hue.hairline`.
   **Over-image** white opacities (85%, 70%) stay as-is — that text sits on a photo.
3. **Monochrome active states.** Like/save/join "active" = `ink` fill, never red/green.
   When the pending accent hue lands, the sanctioned homes for it here are exactly
   *joined state* and *live/active like* (both are "selected state / primary CTA" per
   brand) — until then, ink.
4. **Places attribution** (Google Places photos): `authorAttributions` caption 10pt,
   white 70%, bottom-right inset 8pt — required wherever a Places photo renders.
5. **Voice:** greeting header follows `Evening on the block, Jesse.` (time + "on the
   block" + first name). No cozy/hygge language anywhere.

## Decisions (locked at Phase 0 gate)

1. **Join button = rounded-square**, radius 12, `ink` fill (not a circle). Plus→check
   rotate morph and the ring-burst are preserved; the burst is a **square** stroke.
2. **Title = overlaid on the scrim** (spec), not below the image. Intentional divergence
   from Airbnb/komoot/Strava for a more image-forward card.
3. **Likes render once — on the action-row heart** (`.numericText()`). The facepile line
   carries the "going" avatars + `Sam and 3 others are going` only; no `· 12 likes` there.

---
*Phase 0 gate passed. Phase 1 (feed card) proceeds under these locks.*
