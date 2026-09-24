#!/bin/bash
#
# PreToolUse (Bash): refuse `xcodebuild test` aimed at the screenshot simulator.
#
#   xcodebuild test ... CODE_SIGNING_ALLOWED=NO replaces the installed app with
#   the unsigned test host and WIPES the app container — Keychain session and
#   local mirrors go with it. This signed the primary sim out twice on
#   2026-08-13/14. Keep one sim for screenshots; test on a different device.
#
# Fails OPEN on a missing config. Honours BP_GUARD_OFF=1. Always exits 0.
#
set -u

payload=$(cat)
cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$cmd" ] && exit 0

printf '%s' "$cmd" | grep -q 'xcodebuild' || exit 0
printf '%s' "$cmd" | grep -Eq '(^| )test( |$)' || exit 0

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

if printf '%s' "$cmd" | grep -qF "name=$screenshot_sim"; then
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
