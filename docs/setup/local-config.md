# Local config — required before a fresh clone will build

One source file holds an API key and is gitignored, so it is **not** in the
repo. Without it the build fails with:

```
cannot find 'MAPBOX_ACCESS_TOKEN' in scope
```

That is the intended trade-off — this repo is public, and the keys should never
be in it. But it does mean a fresh clone (new machine, a collaborator, CI) has a
build-blocking step that nothing announced. This file is that announcement.

Create it by hand after cloning. `BlockParty/` is an Xcode file-system
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

## CI

`.github/workflows/ci.yml` writes a **placeholder** when the file is absent. The
test suite is pure logic — it never renders a map — so the placeholder compiles
and passes. If a test ever needs a real key, add a repo
secret and keep the placeholder as the fallback so forks still build.
