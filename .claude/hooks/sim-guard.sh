#!/bin/bash
#
# PreToolUse (Bash): refuse `xcodebuild test` / `test-without-building` aimed at
# the screenshot simulator.
#
#   xcodebuild test ... CODE_SIGNING_ALLOWED=NO replaces the installed app with
#   the unsigned test host and WIPES the app container — Keychain session and
#   local mirrors go with it. This signed the primary sim out twice on
#   2026-08-13/14. Keep one sim for screenshots; test on a different device.
#
# A -destination can name the simulator by name=<name> OR id=<udid> (XcodeBuildMCP
# and plenty of raw invocations use the UDID). The configured name is resolved to
# its current UDID at run time via `simctl` so both forms are caught — never
# hardcode a UDID, a device can be deleted and recreated with a new one.
#
# Fails OPEN on a missing config, a `simctl` that is missing/errors, or a name
# that does not resolve to a UDID — warns on stderr and falls back to (or stays
# on) the name-only check rather than blocking. Honours BP_GUARD_OFF=1. Always
# exits 0.
#
set -u

payload=$(cat)
cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$cmd" ] && exit 0

printf '%s' "$cmd" | grep -q 'xcodebuild' || exit 0
printf '%s' "$cmd" | grep -Eq '(^| )test(-without-building)?( |$)' || exit 0

if [ "${BP_GUARD_OFF:-0}" = "1" ]; then
    printf 'sim-guard: bypassed by BP_GUARD_OFF=1\n' >&2
    exit 0
fi

config="${CLAUDE_PROJECT_DIR:-$PWD}/.claude/guard-config.json"
screenshot_sim=$(jq -r '.screenshotSimulator // empty' "$config" 2>/dev/null)
if [ -z "$screenshot_sim" ]; then
    printf 'sim-guard: %s missing or unreadable — allowing the test run unchecked\n' "$config" >&2
    exit 0
fi

matched=""

# Match a -destination naming the simulator by name=. Extract the value up to
# the next comma/quote/end-of-string first, then compare it whole (-Fx, fixed
# string, whole line) so a configured "iPhone Air" does not also catch a
# destination naming "iPhone Air Pro".
if printf '%s' "$cmd" | grep -oE "name=[^,'\"]*" | sed 's/^name=//' | grep -qFx "$screenshot_sim"; then
    matched=1
fi

# Also match a -destination naming the simulator by id=<udid>, resolved from the
# configured name. A UDID is fixed-format, so a plain substring check is safe.
if [ -z "$matched" ]; then
    screenshot_udid=""
    if command -v xcrun >/dev/null 2>&1; then
        screenshot_udid=$(xcrun simctl list devices -j 2>/dev/null \
            | jq -r --arg n "$screenshot_sim" '[.devices[][]? | select(.name == $n) | .udid][0] // empty' 2>/dev/null)
    fi
    if [ -n "$screenshot_udid" ]; then
        printf '%s' "$cmd" | grep -qF "id=$screenshot_udid" && matched=1
    else
        printf 'sim-guard: could not resolve a UDID for %s via simctl — matching by name only\n' "$screenshot_sim" >&2
    fi
fi

if [ -n "$matched" ]; then
    jq -nc --arg r "A test run on '$screenshot_sim' wipes that simulator's app container — the signed-in session and the local mirrors go with it (this signed the primary sim out twice on 2026-08-13/14). That device is reserved for screenshots. Point -destination at a different simulator: xcrun simctl list devices available. Set BP_GUARD_OFF=1 to override, and say why." '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: $r
      }
    }'
    exit 0
fi

exit 0
