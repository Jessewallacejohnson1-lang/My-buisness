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
# Fails OPEN: a missing or malformed guard-config.json warns and allows, because
# a broken config must never block every edit in a session. Honours BP_GUARD_OFF=1.
# Always exits 0 — a hook must never fail a session.
#
# MultiEdit carries its changes in .tool_input.edits[], each with its own
# new_string, not in .tool_input.new_string — join every edit's new_string too,
# or a MultiEdit that introduces a violation sails through unchecked.
#
# Detection matches the CALL SHAPE, not the literal formatting:
#   - grep -Eq matches per physical line, so a multi-line constructor call
#     (ordinary Swift style for 3-4 argument calls) is flattened to one line
#     first — newlines/whitespace runs collapse to single spaces.
#   - The font check bans Font.system(size:)/Font.custom(...,size:) whatever
#     the argument is (a literal, a constant, extra whitespace before the
#     colon) — the API itself never scales with Dynamic Type, so gating on a
#     numeric literal only catches the laziest violation.
#   - The colour check covers every common constructor shape (red:, hue:,
#     white:, the explicit-.sRGB form, and a quoted hex literal).
#
# tokenFiles/testExemptPrefixes match on PATH SUFFIX/PREFIX, not basename —
# a decoy file that merely shares a name with the real token layer (or sits
# outside BlockPartyTests/BlockPartyUITests) must not inherit the exemption.
# BlockPartyTests/BlockPartyUITests are exempt because the rules themselves
# document literal colour values pinned on purpose there (CreateDiscContrastTests).
#
set -u

payload=$(cat)
path=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
body=$(printf '%s' "$payload" | jq -r '[.tool_input.content? // "", .tool_input.new_string? // "", (.tool_input.edits[]?.new_string // "")] | join("\n")' 2>/dev/null)
# Flatten to one line so a multi-line call still matches a single-line regex.
flat=$(printf '%s' "$body" | tr -s '[:space:]' ' ')

case "$path" in
    *.swift) ;;
    *) exit 0 ;;
esac

if [ "${BP_GUARD_OFF:-0}" = "1" ]; then
    printf 'token-guard: bypassed by BP_GUARD_OFF=1 on %s\n' "$path" >&2
    exit 0
fi

config="${CLAUDE_PROJECT_DIR:-$PWD}/.claude/guard-config.json"
token_files=$(jq -r '.tokenFiles[]?' "$config" 2>/dev/null)
if [ -z "$token_files" ]; then
    printf 'token-guard: %s missing or unreadable — allowing the edit unchecked\n' "$config" >&2
    exit 0
fi

base=$(basename "$path")

# tokenFiles holds path SUFFIXES (e.g. BlockParty/Theme/BlockPartyColor.swift).
# A suffix match, not a basename match, so a same-named decoy elsewhere in
# the tree does not inherit the token layer's exemption.
while IFS= read -r suffix; do
    [ -z "$suffix" ] && continue
    case "$path" in
        *"$suffix") exit 0 ;;
    esac
done <<< "$token_files"

# testExemptPrefixes: directories whose whole job is pinning literal values
# on purpose (see docs/rules/design.md on CreateDiscContrastTests). Matches
# a leading prefix (relative path) or a "/prefix" segment (absolute path).
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

if printf '%s' "$flat" | grep -Eq 'Color\([[:space:]]*\.sRGB[[:space:]]*,|Color\([[:space:]]*red[[:space:]]*:|Color\([[:space:]]*hue[[:space:]]*:|UIColor\([[:space:]]*red[[:space:]]*:|UIColor\([[:space:]]*white[[:space:]]*:|#[0-9A-Fa-f]{6}"'; then
    deny "Hardcoded colour in $base. Colour comes from Hue.* in BlockParty/Theme/BlockPartyColor.swift — add the token there if it is genuinely new. Set BP_GUARD_OFF=1 to override, and say why."
fi

if printf '%s' "$flat" | grep -Eq '\.system\([[:space:]]*size[[:space:]]*:|Font\.custom\([^)]*size[[:space:]]*:'; then
    deny "Frozen font size in $base. Font.system(size:) never scales with Dynamic Type regardless of the argument; text takes a ROLE from BlockPartyFont.swift, which is the only file allowed to name a size. TypographyScalingGuardTests fails the build on this anyway. Set BP_GUARD_OFF=1 to override, and say why."
fi

exit 0
