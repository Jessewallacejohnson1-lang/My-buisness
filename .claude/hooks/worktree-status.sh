#!/bin/bash
#
# SessionStart: report the two kinds of drift that have actually cost time in
# this repo, so a session does not have to discover them the hard way.
#
#   1. This worktree is behind origin/main. Several checkouts share this repo and
#      a new one branched from HEAD rather than the remote starts life stale.
#   2. The app installed on the booted simulator was built somewhere else. Every
#      worktree ships bundle id Jesse.BlockParty, so whichever installed last
#      owns the sim — a screenshot can be a two-day-old binary with no sign of it.
#
# Silent when both are fine. Never fails a session: every probe is guarded and
# the script always exits 0.
#
set -u

cd "${CLAUDE_PROJECT_DIR:-$PWD}" 2>/dev/null || exit 0
command -v git >/dev/null 2>&1 || exit 0
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

notes=""

# 1. Behind the remote. Deliberately does NOT fetch — a network call at session
#    start is a bad trade, and a stale origin/main still catches the common case.
branch=$(git branch --show-current 2>/dev/null)
behind=$(git rev-list --count HEAD..origin/main 2>/dev/null || echo 0)
if [ "${behind:-0}" -gt 0 ] 2>/dev/null; then
    notes="${notes}This worktree (${branch:-detached}) is ${behind} commit(s) behind origin/main as of the last fetch. Catch up with: git fetch origin && git merge --ff-only origin/main"$'\n'
fi

# 2. Whose build is on the simulator.
installed=$(xcrun simctl get_app_container booted Jesse.BlockParty 2>/dev/null)
if [ -n "$installed" ] && [ -f "$installed/BlockParty" ]; then
    installed_sum=$(md5 -q "$installed/BlockParty" 2>/dev/null)
    mine=""
    for plist in "$HOME"/Library/Developer/Xcode/DerivedData/BlockParty-*/info.plist; do
        [ -f "$plist" ] || continue
        workspace=$(/usr/libexec/PlistBuddy -c 'Print :WorkspacePath' "$plist" 2>/dev/null)
        case "$workspace" in
            "$PWD"/*) mine="${plist%/info.plist}/Build/Products/Debug-iphonesimulator/BlockParty.app/BlockParty" ;;
        esac
    done
    if [ -n "$mine" ] && [ -f "$mine" ]; then
        mine_sum=$(md5 -q "$mine" 2>/dev/null)
        if [ -n "$installed_sum" ] && [ "$installed_sum" != "$mine_sum" ]; then
            notes="${notes}The app on the booted simulator was NOT built from this worktree — another checkout installed over it (same bundle id, last install wins). Rebuild and install from here before trusting a screenshot."$'\n'
        fi
    fi
fi

[ -z "$notes" ] && exit 0

jq -nc --arg n "$notes" '{
  systemMessage: $n,
  hookSpecificOutput: { hookEventName: "SessionStart", additionalContext: $n }
}'
exit 0
