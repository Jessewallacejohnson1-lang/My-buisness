# Build, run, verify

Everything needed to build, test, install and screenshot this app. Read it before you
run any of those things, not after one fails.

**Resolve `-destination` against the machine, not from memory.** `[prose]` A simulator name
that does not exist fails the whole invocation with *"Unable to find a device matching the
provided destination specifier"* — which reads like a project problem and is not one.
`xcrun simctl list devices available` lists what is installed, and a failed `xcodebuild`
prints every valid destination for the scheme. Every command below writes `<sim>` rather than
a real name for that reason: substitute one you just looked up. The screenshot device is
reserved and named in `.claude/guard-config.json` — never aim a test run at it.

**Unit tests** live in the `BlockPartyTests` target (app-hosted, so `@testable import BlockParty` works). Run them with:

```bash
xcodebuild test -project BlockParty.xcodeproj -scheme BlockParty \
  -destination 'platform=iOS Simulator,name=<sim>' CODE_SIGNING_ALLOWED=NO
```

A **single** test or class: append `-only-testing:BlockPartyTests/DateHelpersTests/testAdminGate` (or `-only-testing:BlockPartyTests/DateHelpersTests`). Coverage now includes date/admin rules, the Today briefing contract/model/feel/live-payload parity/registry, utility-row providers/preferences/motion/contrast, town-timezone formatting, town-rain physics, the map polish pass (search matching, pin-detail copy, filter-chip semantics, sheet rubber-band math), the horizon layer (solar model, palette, day building, scrub math), and Your Day's realtime relevance filter. **The count is one per `func test` in `BlockPartyTests/` — read it, do not quote a number from here.** It moves under you in this repo: parallel sessions add suites to the same tree, so a figure written down is stale within the day. What matters is the invariant: the executed count must RISE when you add a test (see the registration trap below) and must not fall unless you deleted one on purpose. The horizon, Your Day, trivia and utility suites now test **unmounted** code — they are the proof those parked layers still work, so keep them green rather than deleting them with the surfaces they used to back. It is still mostly pure logic: visual map/feed/sheet/animation fidelity requires a clean 0-warning build plus simulator screenshots, and scroll/gesture behavior requires a real-device check.

- **Run tests on a non-primary simulator.** `[hook]` `xcodebuild test …
  CODE_SIGNING_ALLOWED=NO` replaces the installed app with the unsigned test host and
  wipes that sim's container — Keychain session, `bp.onboarded.<uid>`, local mirrors — on
  whatever sim it targets (it signed the primary sim out twice on 2026-08-13/14). The
  reserved screenshot device is named in `.claude/guard-config.json`; `sim-guard.sh`
  refuses a test run aimed at it. A wiped sim needs a manual sign-in; `-anon-data`
  (`docs/debug-flags.md`) covers read-only screenshot states in the meantime.
  `sim-guard.sh` is registered on a `Bash` matcher, so it only sees `xcodebuild test` run
  through the shell — `mcp__xcodebuildmcp__test_sim` never reaches it, even though
  `CLAUDE.md` says to prefer XcodeBuildMCP for Apple tooling. A test run made through that
  tool needs the same care by hand.
- **A new test file does not run until it is registered.** `[test]` The test targets
  carry an explicit source list; a file under `BlockPartyTests/` or `BlockPartyUITests/`
  is invisible to `xcodebuild test` until 4 `project.pbxproj` entries exist.
  `TestRegistrationGuardTests` fails the suite in both directions. Register with the
  `xcodeproj` gem or the Xcode GUI, never by hand, then confirm the executed count rose.

Raw shell tooling (a session with XcodeBuildMCP should prefer it — see `CLAUDE.md`):

```bash
# Build for the simulator
xcodebuild -project BlockParty.xcodeproj -scheme BlockParty -configuration Debug \
  -destination 'platform=iOS Simulator,name=<sim>' build

# Launch on a booted sim (see debug flags below), then screenshot
# `-open-map` raises the map cover; `-open-tab` takes town|daily|business|you.
xcrun simctl launch <udid> Jesse.BlockParty -open-map
xcrun simctl io <udid> screenshot /tmp/map.png
```

**Installing the build you just made (raw tooling) — the DerivedData trap.** `[prose]` This repo has accumulated **several `BlockParty-<hash>` DerivedData folders** (multiple worktree checkouts), so `find … -name BlockParty.app | head` grabs a **stale** one and you screenshot a days-old binary (symptom: your change is missing, e.g. old theme colors). Resolve the *real* output dir and confirm its timestamp:

```bash
DIR=$(xcodebuild -project BlockParty.xcodeproj -scheme BlockParty -configuration Debug \
  -destination 'platform=iOS Simulator,name=<sim>' -showBuildSettings \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR =/{print $2; exit}')
xcrun simctl install <udid> "$DIR/BlockParty.app"   # install OVER the app — do NOT `uninstall`
```

**A second DerivedData trap: an open Xcode races CLI builds in the shared default DerivedData.** `[prose]` Its background SPM resolution corrupts the binary artifacts mid-run — symptom: `error: There is no XCFramework found at …/artifacts/turf-swift/Turf.xcframework` (or the Mapbox ones) on a build that just succeeded — and it also deletes the worktree's `Package.resolved` (restore with `git checkout --`). One `rm -rf` of the DerivedData folder fixes a single run, but the race comes back; the durable fix is a **dedicated `-derivedDataPath`** for CLI builds and tests whenever Xcode is open (hit twice on 2026-08-19).

`simctl uninstall` wipes the app container: the session and the local profile/interest mirrors go with it, so the next launch is a signed-out one. Install **over** the app. Nothing needs restoring afterwards beyond signing back in — the `bp.onboarded.<uid>` flag stopped gating anything when onboarding was deleted on 2026-09-18.

**Build + install to a physical device (raw tooling — XcodeBuildMCP here exposes only *simulator* workflow tools).** The app uses **Automatic** signing under Jesse's team (`Apple Development: jessewallacejohnson1@icloud.com`) for `Jesse.BlockParty`; the first device build after the identifier change may create or refresh the provisioning profile. Build with `-allowProvisioningUpdates`. The **two device ids differ**: `xcodebuild -destination id=` wants the **hardware UDID** (`xcrun xctrace list devices`), while `devicectl --device` wants the **CoreDevice UUID** (`xcrun devicectl list devices`).

```bash
DD=/tmp/dd-device   # keep DerivedData OUTSIDE BlockParty/, else a stray build dir lands in the sync'd group
xcodebuild -project BlockParty.xcodeproj -scheme BlockParty -configuration Debug \
  -destination 'id=<HARDWARE_UDID>' -derivedDataPath "$DD" -allowProvisioningUpdates build
xcrun devicectl device install app --device <COREDEVICE_UUID> \
  "$DD/Build/Products/Debug-iphoneos/BlockParty.app"          # installs OVER — preserves the container
xcrun devicectl device process launch --device <COREDEVICE_UUID> Jesse.BlockParty
```

A remote `process launch` fails with `RequestDenied … Locked` while the phone is locked — **unlock first**, then relaunch (or just tap the icon). A fresh signing identity may also need a one-time on-device **Settings → General → VPN & Device Management → Trust**.

**DEBUG-only launch arguments** for headless verification (`-open-map`, `-briefing-preview`, `-map-open`, `-show-home`, and ~80 more; all compile out in Release) are catalogued in **`docs/debug-flags.md`** — read it when you need one. The 2026-09-17 strip-down killed a large block of them along with their views; that file has been pruned to what the source actually still parses.

**A green build is not evidence that a visual change landed.** `[prose]` SwiftUI accepts modifiers that do nothing — an outer `foregroundStyle` that a nested one overrides, a gloss composited away by a neighbouring `.glassEffect` surface — and nothing fails. Three such no-ops shipped looking "subtle" before being measured. The loop that catches them: build → install over → `simctl launch` with a debug flag → `simctl io screenshot` (or `recordVideo` + `ffmpeg` frame extraction) → **count actual pixels** in the region you changed. There is no PIL here; a small PNG decoder in `python3` is enough, and the numbers are what settle it.

The same applies to layout: `-feed-scroll-sweep -scroll-log` (see `docs/debug-flags.md`) animates one scroll and prints every offset the scroll reports, and **direction reversals in that trace are the signal** — 0 is healthy, a few hundred means something is ringing. That is how the top bar's inset feedback loop was found, while the build was green and every test passed.

There is no simulator gesture/scroll automation in this setup. Use the targeted galleries/preview flags for below-the-fold states, but still verify real scrolling, taps, and map gestures on a device.

## First-checkout setup — required or the build fails
- **Two gitignored `BlockParty/Config/` files must be recreated** on a fresh clone, or the build will not compile. `[prose]` Which files, what each declares, and where to copy them from: `docs/rules/identifiers.md`.
- **`.impeccable/` build hazard:** the "impeccable" tool drops `.impeccable/hook.cache.json`. If one lands **inside** the `BlockParty/` file-system-synchronized group, Xcode copies duplicate `hook.cache.json` into the bundle and the build fails with **"Multiple commands produce …"**. Fix: `find BlockParty -type d -name .impeccable -exec rm -rf {} +`. (`.impeccable/` is gitignored.)
