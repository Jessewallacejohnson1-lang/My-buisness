#!/bin/bash
#
# PreToolUse (Edit|Write|MultiEdit): refuse a hardcoded colour or a frozen font
# size in a Swift file that is not the token layer.
#
#   Colour comes from Hue.* in BlockPartyColor.swift, type takes a ROLE rather
#   than a point size, and radii come from BlockPartyMetrics. TypographyScaling-
#   GuardTests already fails the build on a frozen font; this stops the edit
#   landing at all, which is a cheaper correction.
#
# Fails OPEN: a missing or malformed guard-config.json notes it and allows, because
# a broken config must never block every edit in a session. Honours BP_GUARD_OFF=1.
# Always exits 0 — a hook must never fail a session.
#
# MultiEdit carries its changes in .tool_input.edits[], each with its own
# new_string, not in .tool_input.new_string — join every edit's new_string too,
# or a MultiEdit that introduces a violation sails through unchecked.
#
# Matches PER PHYSICAL LINE against the body exactly as it arrives — NO
# comment stripping, NO flattening, NO pre-processing of any kind. Three
# earlier rounds tried stripping comments and collapsing multi-line calls
# before matching, and each fix opened a new bypass (an ordinary string
# literal swallowing real code, a raw string defeating quote-counting, a
# block comment merging two lines into a forged call) — that pre-processing
# was trying to be a Swift lexer written in awk/sed, which is not solvable
# in this shape, and every round made the failure surface bigger, not
# smaller. Deleting nothing before matching means nothing can be hidden from
# the regex. The cost: a colour or font call split across multiple lines is
# NOT caught by this hook — see docs/rules/design.md for that limitation in
# plain words. A single-line comment that merely mentions the banned API
# will still deny; that is a known, minor, escapable false positive
# (BP_GUARD_OFF=1) accepted from the very first review.
#
# The colour/font regexes themselves are unchanged from the last round and
# are not the subject of this rewrite — only the pre-processing was removed.
#
# tokenFiles/testExemptPrefixes match on PATH SUFFIX/PREFIX, anchored on a
# "/" boundary (or an exact match), not basename and not a bare string
# suffix — "EvilBlockParty/Theme/BlockPartyColor.swift" must NOT inherit the
# token layer's exemption just because it ends in the same characters.
# "Vendor/BlockParty/Theme/BlockPartyColor.swift" legitimately nests the real
# token layer at a real boundary and does keep it. BlockPartyTests/
# BlockPartyUITests are exempt because the rules themselves document literal
# colour values pinned on purpose there (CreateDiscContrastTests).
#
set -u

payload=$(cat)
path=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
body=$(printf '%s' "$payload" | jq -r '[.tool_input.content? // "", .tool_input.new_string? // "", (.tool_input.edits[]?.new_string // "")] | join("\n")' 2>/dev/null)

case "$path" in
    *.swift) ;;
    *) exit 0 ;;
esac

base=$(basename "$path")

# A bypass or a fail-open says so in one line to the user (systemMessage) and
# the chat (additionalContext): a PreToolUse hook's stderr reaches neither when
# it exits 0. No permissionDecision, so the normal permission flow still runs.
note() {
    jq -nc --arg m "$1" '{systemMessage: $m, hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $m}}'
    exit 0
}

if [ "${BP_GUARD_OFF:-0}" = "1" ]; then
    note "token-guard bypassed by BP_GUARD_OFF=1: colours and font sizes in $base were not checked. Say why the bypass was needed."
fi

config="${CLAUDE_PROJECT_DIR:-$PWD}/.claude/guard-config.json"
token_files=$(jq -r '.tokenFiles[]?' "$config" 2>/dev/null)
if [ -z "$token_files" ]; then
    note "token-guard is off: $config is missing or unreadable, so colours and font sizes in $base were not checked. Restore that file from origin/main."
fi

while IFS= read -r suffix; do
    [ -z "$suffix" ] && continue
    case "$path" in
        "$suffix"|*"/$suffix") exit 0 ;;
    esac
done <<< "$token_files"

test_prefixes=$(jq -r '.testExemptPrefixes[]?' "$config" 2>/dev/null)
while IFS= read -r prefix; do
    [ -z "$prefix" ] && continue
    case "$path" in
        "$prefix"*|*"/$prefix"*) exit 0 ;;
    esac
done <<< "$test_prefixes"

deny() {
    jq -nc --arg r "$1" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: $r
      }
    }'
    exit 0
}

if printf '%s' "$body" | grep -Eq 'Color\([[:space:]]*\.sRGB[[:space:]]*,|Color\([[:space:]]*red[[:space:]]*:|Color\([[:space:]]*hue[[:space:]]*:|UIColor\([[:space:]]*red[[:space:]]*:|UIColor\([[:space:]]*white[[:space:]]*:|#[0-9A-Fa-f]{6}"|#colorLiteral\('; then
    deny "Hardcoded colour in $base. Colour comes from Hue.* in BlockParty/Theme/BlockPartyColor.swift — add the token there if it is genuinely new. Set BP_GUARD_OFF=1 to override, and say why."
fi

if printf '%s' "$body" | grep -Eq '\.system\([[:space:]]*size[[:space:]]*:|Font\.custom\([^)]*size[[:space:]]*:'; then
    deny "Frozen font size in $base. Font.system(size:) never scales with Dynamic Type regardless of the argument; text takes a ROLE from BlockPartyFont.swift, which is the only file allowed to name a size. TypographyScalingGuardTests fails the build on this anyway. Set BP_GUARD_OFF=1 to override, and say why."
fi

exit 0
