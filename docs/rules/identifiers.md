# Identifiers, keys and config files

The live values. Everything here is a fact about the running app, not a preference —
check it before you type an identifier from memory.

- **Bundle id and logging subsystem:** `Jesse.BlockParty`. `[prose]`
- **Xcode project** `BlockParty.xcodeproj` · **scheme** `BlockParty` · **iOS deployment target 26.5** · Swift 5. `[prose]`
- **Shared Supabase project id:** `lxdgwhvqjqmqliobwjpi` — the same project the Expo app uses, and the same one the Android port calls. `[prose]`

## Reference libraries

- **Onboarding reference, Figma team library:** file `BHomEEi7JSfHOiw9DOY6IF`, frame
  `3311:2` (screens `3311:3`–`3311:22`) — the 20 Mobbin captures of Duolingo's iOS
  onboarding. `[prose]` For any *measurement*, prefer the local pixel-scanned frames at
  `refs/onboarding/duolingo/S01–S20.png`; these ids are the provenance.

## The two gitignored config files

- **Two gitignored `BlockParty/Config/` files must be recreated** on a fresh clone (both hold secrets, both are in `.gitignore`, and the build won't compile without the symbols they declare):
  - **`MapboxConfig.swift`** — `let MAPBOX_ACCESS_TOKEN = "pk...."`. Without it the map is blank / the token won't link.
  - **`GooglePlacesConfig.swift`** — `let GOOGLE_PLACES_API_KEY = "AIza...."`. Without it `GooglePlacesService` fails to compile and the runtime venue-photo layer is dead. When recreating a worktree, copy both from an authorized sibling checkout — the handoffs' "copy Config/ back in" step means exactly these two. The Google Cloud key restriction now includes `Jesse.BlockParty` (verified 2026-08-19 — see `DECISIONS.md` §1), so venue photography works under the new bundle id.

## Persisted identifiers and the 2026-08-09 rename

Persisted keys that previously used the product namespace now use `bp.*`; the Keychain account is `bp.session`, and realtime topics are `realtime:bp-<table>`. Do not add new `hygge.*` identifiers. `[prose]`

**There is deliberately no migration shim, and there cannot be one.** iOS scopes `UserDefaults` to the app container and Keychain items to an access group derived from the bundle id, so `Jesse.BlockParty` is a *different app* with an empty container — it cannot read `Jesse.Hygge`'s stored values at all. Bridging would require a shared keychain access group declared in **both** builds, which the already-shipped build does not have and cannot retroactively gain. A migration shim was written, proven to be unreachable dead code, and removed. The rename is therefore a clean break: existing installs re-authenticate and re-onboard. That cost was accepted at 4 accounts / 2 active, pre-launch. See `DECISIONS.md` for the two outstanding console actions required by the new bundle id.
