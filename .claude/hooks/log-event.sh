#!/bin/bash
# Control Room · Panel 3 — ships one Claude Code hook event to Supabase.
#
# Reads the hook JSON from stdin and hands it to a DETACHED python helper, so
# the inline cost of this hook is one process spawn — well inside the 200ms
# budget. The helper does the parsing, git enrichment, and the POST.
#
# SECURITY NOTE (read before registering, per the build spec): hooks run
# automatically with your environment. This script and log-event.py hold no
# secret — the only key involved is the project's PUBLIC anon key, the same
# one that ships inside the app binary. The actual insert happens in the
# log-agent-event edge function, scoped there to the agent_events table.
DIR="$(cd "$(dirname "$0")" && pwd)"
INPUT="$(cat)"
( printf '%s' "$INPUT" | /usr/bin/python3 "$DIR/log-event.py" >/dev/null 2>&1 & )
exit 0
