#!/bin/bash
# Feeds token-guard.sh the payloads it exists to judge and checks each verdict.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
export CLAUDE_PROJECT_DIR="$PWD"
guard=".claude/hooks/token-guard.sh"
fails=0

run() { printf '%s' "$1" | "$guard" 2>/dev/null; }
expect() {
    local name="$1" payload="$2" want="$3"
    local got; got=$(run "$payload" | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null)
    got="${got:-allow}"
    if [ "$got" = "$want" ]; then printf 'ok   %s\n' "$name"
    else printf 'FAIL %s: wanted %s, got %s\n' "$name" "$want" "$got"; fails=$((fails+1)); fi
}

expect "hex colour in a feature file" \
  '{"tool_input":{"file_path":"BlockParty/Features/Town/TownView.swift","content":"let c = Color(red: 0.1, green: 0.2, blue: 0.3)"}}' deny
expect "frozen font in a feature file" \
  '{"tool_input":{"file_path":"BlockParty/Features/Town/TownView.swift","content":".font(.system(size: 17))"}}' deny
expect "frozen font inside a MultiEdit edits[] entry" \
  '{"tool_input":{"file_path":"BlockParty/Features/Town/TownView.swift","edits":[{"old_string":"let n = 1","new_string":"let n = 1"},{"old_string":"old","new_string":".font(.system(size: 17))"}]}}' deny
expect "same colour inside the token layer" \
  '{"tool_input":{"file_path":"BlockParty/Theme/BlockPartyColor.swift","content":"let c = Color(red: 0.1, green: 0.2, blue: 0.3)"}}' allow
expect "a non-Swift file" \
  '{"tool_input":{"file_path":"docs/rules/design.md","content":"Color(red: 0.1, green: 0.2, blue: 0.3)"}}' allow
expect "ordinary Swift with no violation" \
  '{"tool_input":{"file_path":"BlockParty/Features/Town/TownView.swift","content":"let n = 3"}}' allow

mv .claude/guard-config.json .claude/guard-config.json.bak
expect "malformed config fails OPEN" \
  '{"tool_input":{"file_path":"BlockParty/Features/Town/TownView.swift","content":".font(.system(size: 17))"}}' allow
mv .claude/guard-config.json.bak .claude/guard-config.json

BP_GUARD_OFF=1 expect "BP_GUARD_OFF=1 lets it through" \
  '{"tool_input":{"file_path":"BlockParty/Features/Town/TownView.swift","content":".font(.system(size: 17))"}}' allow

exit $fails
