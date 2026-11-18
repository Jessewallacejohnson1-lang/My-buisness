#!/bin/bash
#
# PreToolUse (Bash): block the two git commands that have gone wrong in this
# shared checkout, with the reason attached so the next attempt is the right one.
#
#   git add -A / --all with no path (or ., :/, *, $…, ../…), git add . , git commit -a
#       Several Claude sessions work this tree at once. A blanket stage sweeps
#       whatever another session has in flight into the commit; on 2026-09-19 it
#       took 45 foreign files and was caught only by reading the diff before the
#       push. Stage explicit paths instead; `git add -A <path>...` passes.
#       Tests: .claude/hooks/test-git-guard.sh.
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

# git and its global options, values included (-C <dir>, -c <key=value>).
git_pre='git +((-[Cc] +("[^"]*"|[^ ]+)|-[^ ]+) +)*'

# `git add -A` / `--all` with no path, or a path that can mean everything: ., ./, ../…, /…, :… (pathspec
# magic), a glob (* ? [), or $ / ` (a variable or a command's output, unknown until the shell runs it).
# With named paths it passes, wherever the flag sits: that is how a deletion is staged.
blanket_add() {
    local seg args a all paths wide
    while IFS= read -r seg; do
        seg="${seg#"${seg%%[! ]*}"}"
        printf '%s' "$seg" | grep -Eq "^${git_pre}add( |$)" || continue
        args=$(printf '%s' "$seg" | sed -E "s/^${git_pre}add//")
        all=0 paths=0 wide=0
        set -f
        for a in $args; do
            a="${a//\"/}"; a="${a//\'/}"
            case "$a" in
                --all) all=1 ;;
                --*|'') ;;
                -*A*) all=1 ;;
                -*) ;;
                .|./|..*|/*|:*|*[*?[]*|*'$'*|*'`'*) paths=1 wide=1 ;;  # pathspec magic, a glob, a variable or $(…), absolute
                *) paths=1 ;;
            esac
        done
        set +f
        [ "$all" = 1 ] && { [ "$paths" = 0 ] || [ "$wide" = 1 ]; } && return 0
    done < <(printf '%s\n' "$cmd" | tr ';&|()' '\n\n\n\n\n')
    return 1
}

# Blanket staging: the above, a bare `git add .`, and the `-a` shorthand on
# commit (including combined flags like -am).
if [ "${BP_GUARD_OFF:-0}" != "1" ] \
   && { blanket_add \
   || printf '%s' "$cmd" | grep -Eq "(^|[;&|] *)${git_pre}add +\.( |\$|;|&)" \
   || printf '%s' "$cmd" | grep -Eq "(^|[;&|] *)${git_pre}commit +([^;&|]* )?-[a-zA-Z]*a([a-zA-Z]*)?( |\$)"; }; then
    deny "Blanket staging is blocked in this repo: parallel Claude sessions share these worktrees, and a wildcard stage takes their in-flight work with yours (it swept 45 foreign files on 2026-09-19). Stage the paths you actually changed: git add <path> [<path>...]. To stage a deletion with them: git add -A <path> [<path>...]. Check with: git status --porcelain. If you genuinely want everything, say so and the user can run it themselves."
fi

# A worktree created without a start-point inherits the current HEAD.
if [ "${BP_GUARD_OFF:-0}" != "1" ] \
   && printf '%s' "$cmd" | grep -Eq '(^|[;&|] *)git +(-[^ ]+ +)*worktree +add( |$)'; then
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
