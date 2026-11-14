#!/bin/bash
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
export CLAUDE_PROJECT_DIR="$PWD"
sim=$(jq -r '.screenshotSimulator' .claude/guard-config.json)
passes=0 fails=0

pass() { printf 'ok   %s\n' "$1"; passes=$((passes+1)); }
fail() { printf 'FAIL %s\n' "$1"; fails=$((fails+1)); }

expect() {
    local name="$1" payload="$2" want="$3"
    local got
    got=$(printf '%s' "$payload" | .claude/hooks/sim-guard.sh 2>/dev/null \
          | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null)
    got="${got:-allow}"
    if [ "$got" = "$want" ]; then pass "$name"; else fail "$name: wanted $want, got $got"; fi
}

# A bypass or fail-open allows the call and prints one line, the same to the
# user (systemMessage) and the chat (additionalContext), with no decision. An
# empty $want means an ordinary allowed call: no output at all.
says() {
    local name="$1" payload="$2" want="$3" out line
    out=$(printf '%s' "$payload" | .claude/hooks/sim-guard.sh 2>/dev/null)
    line=$(printf '%s' "$out" | jq -r 'select(.hookSpecificOutput.permissionDecision == null
        and .hookSpecificOutput.additionalContext == .systemMessage) | .systemMessage' 2>/dev/null)
    if { [ -z "$want" ] && [ -z "$out" ]; } || { [ -n "$want" ] && printf '%s' "$line" | grep -qF "$want"; }
    then pass "$name"; else fail "$name: wanted ${want:-no output}, got ${out:-no output}"; fi
}

expect "test on the screenshot sim" \
  "{\"tool_input\":{\"command\":\"xcodebuild test -scheme BlockParty -destination 'platform=iOS Simulator,name=$sim'\"}}" deny
expect "test on another sim" \
  '{"tool_input":{"command":"xcodebuild test -scheme BlockParty -destination '"'"'platform=iOS Simulator,name=BlockParty Tests'"'"'"}}' allow
expect "a plain build on the screenshot sim" \
  "{\"tool_input\":{\"command\":\"xcodebuild -scheme BlockParty -destination 'platform=iOS Simulator,name=$sim' build\"}}" allow
expect "an unrelated command" \
  '{"tool_input":{"command":"ls -la"}}' allow
BP_GUARD_OFF=1 expect "BP_GUARD_OFF=1 lets it through" \
  "{\"tool_input\":{\"command\":\"xcodebuild test -scheme BlockParty -destination 'platform=iOS Simulator,name=$sim'\"}}" allow
BP_GUARD_OFF=1 says "BP_GUARD_OFF=1 in the environment says it was bypassed" \
  "{\"tool_input\":{\"command\":\"xcodebuild test -scheme BlockParty -destination 'platform=iOS Simulator,name=$sim'\"}}" "sim-guard bypassed by BP_GUARD_OFF=1"
says "BP_GUARD_OFF=1 written in front of the command bypasses and says so" \
  "{\"tool_input\":{\"command\":\"BP_GUARD_OFF=1 xcodebuild test -scheme BlockParty -destination 'platform=iOS Simulator,name=$sim'\"}}" "sim-guard bypassed by BP_GUARD_OFF=1"
expect "the prefix after cd && also bypasses" \
  "{\"tool_input\":{\"command\":\"cd /tmp && BP_GUARD_OFF=1 xcodebuild test -destination 'platform=iOS Simulator,name=$sim'\"}}" allow
expect "BP_GUARD_OFF=1 inside a longer name is not a bypass" \
  "{\"tool_input\":{\"command\":\"XBP_GUARD_OFF=1 xcodebuild test -destination 'platform=iOS Simulator,name=$sim'\"}}" deny
CLAUDE_PROJECT_DIR=/nonexistent says "missing config allows and says the guard is off" \
  "{\"tool_input\":{\"command\":\"xcodebuild test -destination 'platform=iOS Simulator,name=$sim'\"}}" "sim-guard is off"
says "an ordinary allowed test run prints nothing" \
  '{"tool_input":{"command":"xcodebuild test -scheme BlockParty -destination '"'"'platform=iOS Simulator,name=BlockParty Tests'"'"'"}}' ""

# UDID-addressed destinations (fix round 1, finding 1). XcodeBuildMCP and plenty
# of raw invocations address a simulator by id=<udid>, not name=. Resolve both
# devices' current UDIDs at run time — never hardcode, a sim can be deleted and
# recreated with a new one — and confirm the guard catches the id= form too.
sim_udid=$(xcrun simctl list devices -j 2>/dev/null | jq -r --arg n "$sim" '[.devices[][]? | select(.name == $n) | .udid][0] // empty')
other_udid=$(xcrun simctl list devices -j 2>/dev/null | jq -r '[.devices[][]? | select(.name == "BlockParty Tests") | .udid][0] // empty')

if [ -n "$sim_udid" ]; then
    expect "test on the screenshot sim, addressed by id=" \
      "{\"tool_input\":{\"command\":\"xcodebuild test -destination 'platform=iOS Simulator,id=$sim_udid'\"}}" deny
else
    printf 'SKIP test on the screenshot sim, addressed by id=: could not resolve "%s" to a UDID on this machine\n' "$sim"
fi

if [ -n "$other_udid" ]; then
    expect "test on another sim, addressed by id=" \
      "{\"tool_input\":{\"command\":\"xcodebuild test -destination 'platform=iOS Simulator,id=$other_udid'\"}}" allow
else
    printf 'SKIP test on another sim, addressed by id=: could not resolve "BlockParty Tests" to a UDID on this machine\n'
fi

# test-without-building also replaces the installed app with the unsigned test
# host (fix round 1, minor a) — same container-wipe risk as `test`.
expect "test-without-building on the screenshot sim" \
  "{\"tool_input\":{\"command\":\"xcodebuild test-without-building -destination 'platform=iOS Simulator,name=$sim'\"}}" deny

# A device name that merely starts with the configured name must not be caught
# (fix round 1, minor b) — "iPhone Air Pro" is a different device from "iPhone Air".
expect "a device name sharing the screenshot sim's prefix is not caught" \
  "{\"tool_input\":{\"command\":\"xcodebuild test -destination 'platform=iOS Simulator,name=$sim Pro'\"}}" allow

# simctl missing/erroring fails OPEN: falls back to the name-only check (which
# finds nothing here, since this destination only carries id=) rather than
# blocking the command outright.
if [ -n "$sim_udid" ]; then
    tmpbin=$(mktemp -d)
    printf '#!/bin/sh\nexit 1\n' > "$tmpbin/xcrun"
    chmod +x "$tmpbin/xcrun"
    PATH="$tmpbin:$PATH" expect "simctl unavailable falls back to allow, not deny" \
      "{\"tool_input\":{\"command\":\"xcodebuild test -destination 'platform=iOS Simulator,id=$sim_udid'\"}}" allow
    PATH="$tmpbin:$PATH" says "simctl unavailable says it checked by name only" \
      "{\"tool_input\":{\"command\":\"xcodebuild test -destination 'platform=iOS Simulator,id=$sim_udid'\"}}" "by simulator name only"
    rm -rf "$tmpbin"
else
    printf 'SKIP simctl unavailable falls back to allow, not deny: could not resolve "%s" to a UDID on this machine\n' "$sim"
fi

printf '%d passed, %d failed\n' "$passes" "$fails"
exit $fails
