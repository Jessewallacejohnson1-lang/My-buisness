#!/bin/bash
# Feeds token-guard.sh the payloads it exists to judge and checks each verdict.
#
# token-guard.sh matches PER PHYSICAL LINE with no comment-stripping and no
# flattening (fix round 4 deleted all of that pre-processing — see the
# script's header and docs/rules/design.md for why). So this harness only
# covers single-line violations, the path-suffix/prefix exemptions, the
# fail-open and BP_GUARD_OFF=1 paths, the two live bypasses that pre-
# processing rounds 1-3 opened and are now closed by deleting the mechanism
# that opened them, and one case documenting the accepted residual gap: a
# colour/font call split across physical lines is not caught here.
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

expect "explicit-colour-space Color(.sRGB, red: ...) constructor" \
  '{"tool_input":{"file_path":"BlockParty/Features/Town/TownView.swift","content":"let c = Color(.sRGB, red: 0.1, green: 0.2, blue: 0.3)"}}' deny
expect "UIColor(white:alpha:) constructor" \
  '{"tool_input":{"file_path":"BlockParty/Features/Town/TownView.swift","content":"let c = UIColor(white: 0.5, alpha: 1.0)"}}' deny
expect "space before the colon: Font.system(size : 17)" \
  '{"tool_input":{"file_path":"BlockParty/Features/Town/TownView.swift","content":"Font.system(size : 17)"}}' deny
expect "a constant, not a literal: .system(size: someConstant)" \
  '{"tool_input":{"file_path":"BlockParty/Features/Town/TownView.swift","content":".font(.system(size: someConstant))"}}' deny
expect "#colorLiteral is a hardcoded colour too" \
  '{"tool_input":{"file_path":"BlockParty/Features/Town/TownView.swift","content":"let c = #colorLiteral(red: 1, green: 0, blue: 0, alpha: 1)"}}' deny

expect "BlockPartyColor.swift OUTSIDE BlockParty/Theme/ does not inherit the exemption" \
  '{"tool_input":{"file_path":"BlockParty/Features/Rogue/BlockPartyColor.swift","content":"let c = Color(red: 0.1, green: 0.2, blue: 0.3)"}}' deny
expect "EvilBlockParty/Theme/BlockPartyColor.swift does not inherit the exemption (unanchored suffix)" \
  '{"tool_input":{"file_path":"EvilBlockParty/Theme/BlockPartyColor.swift","content":"let c = Color(red: 0.1, green: 0.2, blue: 0.3)"}}' deny
expect "Vendor/BlockParty/Theme/BlockPartyColor.swift is a real nested copy — exempt" \
  '{"tool_input":{"file_path":"Vendor/BlockParty/Theme/BlockPartyColor.swift","content":"let c = Color(red: 0.1, green: 0.2, blue: 0.3)"}}' allow
expect "CreateDiscContrastTests pins a literal on purpose — exempt" \
  '{"tool_input":{"file_path":"BlockPartyTests/CreateDiscContrastTests.swift","content":"let onCreateDiscHex = Color(red: 0.05, green: 0.05, blue: 0.05)"}}' allow

# --- fix round 4: rounds 1-3's pre-processing (comment stripping, flattening,
# quote-counting, block-comment removal) is DELETED, not patched again. Its
# own two live bypasses are proven closed by the deletion itself. ---

expect "a fake /* inside a string literal no longer swallows the real call after it" \
  '{"tool_input":{"file_path":"BlockParty/Features/Town/TownView.swift","content":"let s = \"look /* fake open\"; Color(red: 0.1, green: 0.2, blue: 0.3); /* real */ let n = 3"}}' deny
expect "a Swift raw string literal no longer defeats detection" \
  '{"tool_input":{"file_path":"BlockParty/Features/Town/TownView.swift","content":"let x = #\"a\"//real \"# ; Color(red: 0.1, green: 0.2, blue: 0.3)"}}' deny
expect "ACCEPTED GAP: a colour call split across physical lines is not caught" \
  '{"tool_input":{"file_path":"BlockParty/Features/Town/TownView.swift","content":"Color(\n    red: 0.1, green: 0.2, blue: 0.3\n)"}}' allow

mv .claude/guard-config.json .claude/guard-config.json.bak
expect "malformed config fails OPEN" \
  '{"tool_input":{"file_path":"BlockParty/Features/Town/TownView.swift","content":".font(.system(size: 17))"}}' allow
mv .claude/guard-config.json.bak .claude/guard-config.json

BP_GUARD_OFF=1 expect "BP_GUARD_OFF=1 lets it through" \
  '{"tool_input":{"file_path":"BlockParty/Features/Town/TownView.swift","content":".font(.system(size: 17))"}}' allow

exit $fails
