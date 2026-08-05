# Local config — required before a fresh clone will build

Two source files hold API keys and are gitignored, so they are **not** in the
repo. Without them the build fails with:

```
cannot find 'MAPBOX_ACCESS_TOKEN' in scope
cannot find 'GOOGLE_PLACES_API_KEY' in scope
```

That is the intended trade-off — this repo is public, and the keys should never
be in it. But it does mean a fresh clone (new machine, a collaborator, CI) has a
build-blocking step that nothing announced. This file is that announcement.

Create both by hand after cloning. `BlockParty/` is an Xcode file-system
synchronized group, so the files are picked up automatically — there is nothing
to add to `project.pbxproj`.

## `BlockParty/Config/MapboxConfig.swift`

```swift
//  Mapbox public access token. Gitignored — never commit.
//  Get one at https://account.mapbox.com/access-tokens/
let MAPBOX_ACCESS_TOKEN = "pk.your-token-here"
```

Used by `BlockParty/BlockPartyApp.swift` (`MapboxOptions.accessToken`).

A `pk.` token is a *public* token and is meant to ship inside the client — the
map cannot work otherwise. That is not a leak, but it does mean anyone with the
app binary has it, so **restrict it** in the Mapbox dashboard (URL / bundle-ID
restrictions and a scoped token) or an extracted token can run up your bill.

## `BlockParty/Config/GooglePlacesConfig.swift`

```swift
//  Google Places API key. Gitignored — never commit.
//  Get one at https://console.cloud.google.com/apis/credentials
let GOOGLE_PLACES_API_KEY = "your-key-here"
```

Used by `BlockParty/Backend/GooglePlacesService.swift` (sent as the
`X-Goog-Api-Key` header).

Unlike the Mapbox token this one is sent from the device to Google directly, so
it is extractable from the binary too. Restrict it to the iOS bundle identifier
and to the Places API only in the Cloud console.

## CI

`.github/workflows/ci.yml` writes **placeholder** values for both when the files
are absent. The test suite is pure logic — it never renders a map or calls Places
— so placeholders compile and pass. If a test ever needs a real key, add a repo
secret and keep the placeholder as the fallback so forks still build.
