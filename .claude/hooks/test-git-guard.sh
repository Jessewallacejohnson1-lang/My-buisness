#!/bin/bash
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
passes=0 fails=0

pass() { printf 'ok   %s\n' "$1"; passes=$((passes+1)); }
fail() { printf 'FAIL %s\n' "$1"; fails=$((fails+1)); }

expect() {
    local name="$1" cmd="$2" want="$3"
    local got
    got=$(jq -nc --arg c "$cmd" '{tool_input:{command:$c}}' | .claude/hooks/git-guard.sh 2>/dev/null \
          | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null)
    got="${got:-allow}"
    if [ "$got" = "$want" ]; then pass "$name"; else fail "$name: wanted $want, got $got"; fi
}

# Blanket staging stays stopped: no path, or a path that means everything.
expect "git add -A"                    'git add -A' deny
expect "git add --all"                 'git add --all' deny
expect "git add ."                     'git add .' deny
expect "git add -A ."                  'git add -A .' deny
expect "git add -A :/"                 'git add -A :/' deny
expect "git add -A *"                  'git add -A "*"' deny
expect "git add -A ../other"           'git add -A ../other' deny
expect "git add -A <file> ../other"    'git add -A a.swift ../other' deny
expect "git add -A ':(top)'"           "git add -A ':(top)'" deny
expect "git add -A ':!secret'"         "git add -A ':!secret'" deny
expect "git add -A './*'"              "git add -A './*'" deny
expect "git add -A '**'"               "git add -A '**'" deny
# A redirection or a comment is not a path (review check, 2026-11-18).
expect "git add -A 2>/dev/null"        'git add -A 2>/dev/null' deny
expect "git add -A >/dev/null"         'git add -A >/dev/null' deny
expect "git add -A # stage"            'git add -A # stage' deny
# Spellings of the whole tree.
expect "git add -A \\."                'git add -A \.' deny
expect "git add -A ./."                'git add -A ./.' deny
expect "git add -A .//"                'git add -A .//' deny
expect "git add -A <dir>/.."           'git add -A BlockParty/..' deny
expect "git add -A ~/<repo>"           'git add -A ~/Documents/bp-ag-24' deny
expect "git add -A {.,a.swift}"        'git add -A {.,a.swift}' deny
expect "git add -A <file> *.swift"     'git add -A a.swift "*.swift"' deny
expect "git add -A a?.swift"           'git add -A a?.swift' deny
expect "git add -A [ab].swift"         'git add -A [ab].swift' deny
expect "git add -A \"\$PWD\""           'git add -A "$PWD"' deny
expect "git add -A \$(git ls-files -m)" 'git add -A $(git ls-files -m)' deny
expect "git add -A \`git ls-files\`"   'git add -A `git ls-files -m`' deny
expect "git add -A <absolute path>"    'git add -A /Users/owner/Documents/bp-ag-24' deny
expect "git add -A ./"                 'git add -A ./' deny
expect "git add -A .."                 'git add -A ..' deny
expect "git -C <dir> add -A"           'git -C /tmp/wt add -A' deny
expect "git add -A after cd &&"        'cd /tmp/wt && git add -A' deny
expect "git commit -a"                 'git commit -a' deny
expect "git commit -am \"x\""          'git commit -am "x"' deny

# Named paths pass, wherever -A sits: the way to stage a deletion too.
expect "git add -A <file> <file>"      'git add -A BlockParty/A.swift docs/debug-flags.md' allow
expect "git add <file> -A"             'git add BlockParty/A.swift -A' allow
expect "git add -A ./<file>"           'git add -A ./BlockParty/A.swift' allow
expect "git add --all <dir>"           'git add --all BlockParty BlockPartyTests' allow
expect "git -C <dir> add -A <file>"    'git -C /tmp/wt add -A BlockParty/A.swift' allow
expect "git add -A <file> && commit"   'git add -A a.swift && git commit -m "fix: x"' allow
expect "git add <file>"                'git add BlockParty/A.swift' allow
expect "git commit -m"                 'git commit -m "add a thing"' allow

# The refusal names the form that stages a deletion.
reason=$(jq -nc '{tool_input:{command:"git add -A"}}' | .claude/hooks/git-guard.sh \
         | jq -r '.hookSpecificOutput.permissionDecisionReason // empty')
if printf '%s' "$reason" | grep -qF 'git add -A <path> [<path>...]'; then pass "refusal names git add -A <path>"
else fail "refusal names git add -A <path>: got ${reason:-nothing}"; fi

printf '%d passed, %d failed\n' "$passes" "$fails"
exit $fails
