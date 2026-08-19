#!/usr/bin/env python3
"""Control Room / Panel 3 -- POST one Claude Code hook event to Supabase.

Runs detached (log-event.sh backgrounds it), so nothing here can block or
fail a Claude Code turn: every failure path is a silent return, and the
worst case is one missing log row.

The embedded key is the project's PUBLIC anon key -- identical to the one
shipped in the app binary; RLS gives it no direct table access. The insert
happens inside the log-agent-event edge function with its own credentials.

prompt_id: generated on UserPromptSubmit and parked in /tmp keyed by
session_id, so every later event in the same prompt carries the same id.
"""
import json
import os
import subprocess
import sys
import urllib.request
import uuid

FUNCTION_URL = "https://lxdgwhvqjqmqliobwjpi.supabase.co/functions/v1/log-agent-event"
ANON_KEY = (
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
    "eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imx4ZGd3aHZxanFtcWxpb2J3anBpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODExMjU3MTEsImV4cCI6MjA5NjcwMTcxMX0."
    "WrwYA1NN8pOy5iOqljBJHys15CqpVAbUEFeqiriwmb0"
)
REPO = "ios"
SUMMARY_MAX = 300
TEXT_FIELD_MAX = 400
POST_TIMEOUT_S = 5
GIT_TIMEOUT_S = 3


def main() -> None:
    try:
        hook = json.load(sys.stdin)
    except Exception:
        return
    if not isinstance(hook, dict):
        return

    event = hook.get("hook_event_name") or ""
    if not event:
        return
    session = hook.get("session_id") or ""
    cwd = hook.get("cwd") or os.getcwd()

    tool_input = hook.get("tool_input")
    file_path = tool_input.get("file_path") if isinstance(tool_input, dict) else None
    tool_name = hook.get("tool_name")

    summary_bits = [bit for bit in (event, tool_name, relative(file_path, cwd)) if bit]
    row = {
        "session_id": session or None,
        "prompt_id": prompt_id_for(event, session),
        "event": event,
        "tool_name": tool_name,
        "repo": REPO,
        "branch": current_branch(cwd),
        "file_path": file_path,
        "summary": " ".join(summary_bits)[:SUMMARY_MAX] or None,
        "raw": slim(hook),
    }

    request = urllib.request.Request(
        FUNCTION_URL,
        data=json.dumps(row).encode(),
        headers={
            "Authorization": f"Bearer {ANON_KEY}",
            "apikey": ANON_KEY,
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        urllib.request.urlopen(request, timeout=POST_TIMEOUT_S).read()
    except Exception:
        pass


def prompt_id_for(event: str, session: str) -> "str | None":
    park = f"/tmp/claude-bp-prompt-id-{session or 'unknown'}"
    if event == "UserPromptSubmit":
        fresh = str(uuid.uuid4())
        try:
            with open(park, "w") as f:
                f.write(fresh)
        except OSError:
            pass
        return fresh
    try:
        with open(park) as f:
            return f.read().strip() or None
    except OSError:
        return None


def current_branch(cwd: str) -> "str | None":
    try:
        out = subprocess.run(
            ["git", "-C", cwd, "rev-parse", "--abbrev-ref", "HEAD"],
            capture_output=True,
            text=True,
            timeout=GIT_TIMEOUT_S,
        )
        return out.stdout.strip() or None
    except Exception:
        return None


def relative(path: "str | None", cwd: str) -> "str | None":
    if not path:
        return None
    return os.path.relpath(path, cwd) if path.startswith(cwd) else path


def slim(hook: dict) -> dict:
    """The raw payload, minus anything heavy: tool_input can carry whole file
    contents, and tool_response can carry whole tool results. Values keep
    their shape; long strings become a length marker."""
    out = dict(hook)
    tool_input = out.get("tool_input")
    if isinstance(tool_input, dict):
        out["tool_input"] = {key: clip(value) for key, value in tool_input.items()}
    out.pop("tool_response", None)
    return out


def clip(value: object) -> object:
    if isinstance(value, (int, float, bool)) or value is None:
        return value
    text = value if isinstance(value, str) else json.dumps(value, default=str)
    return text if len(text) <= TEXT_FIELD_MAX else f"<{len(text)} chars>"


main()
