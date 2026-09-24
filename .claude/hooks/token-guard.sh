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
set -u

payload=$(cat)
path=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
body=$(printf '%s' "$payload" | jq -r '[.tool_input.content? // "", .tool_input.new_string? // "", (.tool_input.edits[]?.new_string // "")] | join("\n")' 2>/dev/null)

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
while IFS= read -r allowed; do
    [ "$base" = "$allowed" ] && exit 0
done <<< "$token_files"

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

if printf '%s' "$body" | grep -Eq 'Color\(red:|Color\(#|#[0-9A-Fa-f]{6}"|UIColor\(red:'; then
    deny "Hardcoded colour in $base. Colour comes from Hue.* in BlockParty/Theme/BlockPartyColor.swift — add the token there if it is genuinely new. Set BP_GUARD_OFF=1 to override, and say why."
fi

if printf '%s' "$body" | grep -Eq '\.system\(size: *[0-9]|Font\.custom\([^)]*size: *[0-9]'; then
    deny "Frozen font size in $base. Font.system(size:) never scales with Dynamic Type; text takes a ROLE from BlockPartyFont.swift, which is the only file allowed to name a size. TypographyScalingGuardTests fails the build on this anyway. Set BP_GUARD_OFF=1 to override, and say why."
fi

exit 0
