#!/bin/bash
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
export CLAUDE_PROJECT_DIR="$PWD"
sim=$(jq -r '.screenshotSimulator' .claude/guard-config.json)
fails=0

expect() {
    local name="$1" payload="$2" want="$3"
    local got
    got=$(printf '%s' "$payload" | .claude/hooks/sim-guard.sh 2>/dev/null \
          | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null)
    got="${got:-allow}"
    if [ "$got" = "$want" ]; then printf 'ok   %s\n' "$name"
    else printf 'FAIL %s: wanted %s, got %s\n' "$name" "$want" "$got"; fails=$((fails+1)); fi
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

exit $fails
