# AGENTS.md

**This file is the source of truth for this repository.** Every agent that works here —
Claude Code, Codex, Gemini, Copilot, Aider, a background worktree session — reads it first
and obeys it. It is a **router**, not a manual: it holds how Jesse works, what *done*
means, the rules no machine can check, and a table naming the one file to read before you
act. Everything else lives under `docs/rules/` and loads only when the table sends you.

Precedence when sources disagree: **the code wins, then `MEMORY.md`, then this file.**
Surface the mismatch rather than inventing a path or an API around it.

Written for Jesse, who is not a developer. Explain things accordingly.

**This file is generated.** `[ci]` Edit `rules/router/*.md`, then run
`python3 scripts/bp_rules.py build`. A hand-edit fails `bp_rules.py check`.
