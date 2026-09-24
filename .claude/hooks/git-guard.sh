#!/bin/bash
#
# PreToolUse (Bash): block the two git commands that have gone wrong in this
# shared checkout, with the reason attached so the next attempt is the right one.
#
#   git add -A / --all / . , and git commit -a
#       Several Claude sessions work this tree at once. A blanket stage sweeps
#       whatever another session has in flight into the commit; on 2026-09-19 it
#       took 45 foreign files and was caught only by reading the diff before the
#       push. Stage explicit paths instead.
#
#   git worktree add <path> -b <branch>   with no start-point
#       Without one, git branches from the CURRENT HEAD, so a worktree created
#       from a stale checkout is born behind. Name the remote: origin/main.
#
# Exits 0 with an allow decision for everything else, and stays silent doing it.
#
set -u

payload=$(cat)
cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$cmd" ] && exit 0

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

# Blanket staging. Matches `git add -A`, `--all`, a bare `git add .`, and the
# `-a` shorthand on commit (including combined flags like -am).
if printf '%s' "$cmd" | grep -Eq '(^|[;&|] *)git +(-[^ ]+ +)*add +([^;&|]* )?(-A|--all)( |$)' \
   || printf '%s' "$cmd" | grep -Eq '(^|[;&|] *)git +(-[^ ]+ +)*add +\.( |$|;|&)' \
   || printf '%s' "$cmd" | grep -Eq '(^|[;&|] *)git +(-[^ ]+ +)*commit +([^;&|]* )?-[a-zA-Z]*a([a-zA-Z]*)?( |$)'; then
    deny "Blanket staging is blocked in this repo: parallel Claude sessions share these worktrees, and a wildcard stage takes their in-flight work with yours (it swept 45 foreign files on 2026-09-19). Stage the paths you actually changed: git add <path> [<path>...]. Check with: git status --porcelain. If you genuinely want everything, say so and the user can run it themselves."
fi

# A worktree created without a start-point inherits the current HEAD.
if printf '%s' "$cmd" | grep -Eq '(^|[;&|] *)git +(-[^ ]+ +)*worktree +add( |$)'; then
    if ! printf '%s' "$cmd" | grep -Eq 'origin/|--detach|[0-9a-f]{7,40}'; then
        deny "git worktree add without a start-point branches from the CURRENT HEAD, so the new worktree starts as stale as this one. Name the remote explicitly: git worktree add <path> -b <branch> origin/main (fetch first)."
    fi
fi

# A commit or push landing on a branch this session did not start on. A parallel
# session can move this worktree mid-task; on 2026-09-19 a commit landed on a
# sibling's feat/dynamic-type that way.
if [ "${BP_GUARD_OFF:-0}" != "1" ] \
   && printf '%s' "$cmd" | grep -Eq '(^|[;&|] *)git +(-[^ ]+ +)*(commit|push)( |$)'; then
    started_file=$(git rev-parse --git-path bp-session-branch 2>/dev/null)
    if [ -n "${started_file:-}" ] && [ -f "$started_file" ]; then
        started=$(cat "$started_file" 2>/dev/null)
        current=$(git branch --show-current 2>/dev/null)
        if [ -n "$started" ] && [ -n "$current" ] && [ "$started" != "$current" ]; then
            deny "This session started on '$started' but the worktree is now on '$current'. A parallel session moved it, and a commit here lands on someone else's branch (this happened on 2026-09-19). Confirm where this work belongs: git branch --show-current, git status --short. If '$current' is genuinely right, re-baseline with: git branch --show-current > \"$started_file\". Set BP_GUARD_OFF=1 to override, and say why."
        fi
    fi
fi

exit 0
