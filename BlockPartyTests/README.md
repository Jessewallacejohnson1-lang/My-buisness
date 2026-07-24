# BlockPartyTests

The first unit-test slice (pure, brand-critical logic) + the fake that the
`TokenProviding` seam unlocks.

**The `BlockPartyTests` target is now wired** (app-hosted unit-test bundle, added via the
`xcodeproj` Ruby gem — safe for this objectVersion-77 / synchronized-group project). Run:

```bash
xcodebuild test -project BlockParty.xcodeproj -scheme BlockParty \
  -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO
# single test: add -only-testing:BlockPartyTests/DateHelpersTests/testAdminGate
```

## Re-creating the target from scratch (one time, ~15 seconds in Xcode)

The project is the new format (objectVersion 77, file-system-synchronized groups).
Adding a target is a one-click GUI action — safer than hand-editing `project.pbxproj`:

1. **File ▸ New ▸ Target… ▸ Unit Testing Bundle** → name it `BlockPartyTests`, "Target to be Tested" = `BlockParty`.
2. Xcode creates the target + a `BlockPartyTests/` group. Delete its generated sample file.
3. Add the two files here (`DateHelpersTests.swift`, `FakeTokenProvider.swift`) to the `BlockPartyTests` target (drag in, or right-click ▸ Add Files, check the BlockPartyTests target).
4. Run: `xcodebuild test -project BlockParty.xcodeproj -scheme BlockParty -destination 'platform=iOS Simulator,name=iPhone 17'`
   (or ⌘U in Xcode).

## What's covered (Phase 1)

`DateHelpersTests` — `minutesOf` (incl. the "midnight" regression), `isLiveNow`
boundaries (start / start+120), `daysBetween`, and the `Admin` allowlist.

## Next (per REVIEW.md)

- Extract `MapModel`'s realtime relevance reducer into a free function and test it
  against synthetic INSERT/UPDATE/DELETE `Change` values.
- Decoding tests for `Models.swift` `Codable` structs against fixture JSON.
- `CommunityAPI` against `FakeTokenProvider` (the seam's payoff).
