# CLAUDE.md

**`AGENTS.md` is the source of truth for this repository.** Project rules, build and
verification commands, architecture, the design system, and the trap list all live there,
in detail. This file exists only to load it and to hold the few things that apply to
Claude Code and to no other agent.

The full rules load with this line:

@AGENTS.md

Jesse's standing corrections load with this one:

@MEMORY.md

Precedence when sources disagree: **the code wins, then `AGENTS.md`, then this file.**
Surface the mismatch rather than inventing a path or an API around it.

## Claude-only notes

- **Prefer XcodeBuildMCP** (`build_run_sim`, `build_sim`, `screenshot`) over raw shell for
  Apple tooling. The raw `xcodebuild` / `xcrun simctl` fallbacks in `AGENTS.md` are there
  for sessions without it. Run `session_show_defaults` before a build: every worktree
  builds the same bundle id `Jesse.BlockParty`, so installing any of them overwrites the
  same simulator app and the last build wins.
- **Use `graphify` first for codebase questions** when `graphify-out/graph.json` exists —
  `graphify query`, `graphify path`, `graphify explain` return a scoped subgraph far
  smaller than `GRAPH_REPORT.md` or raw grep. Run `graphify update .` after modifying code.
- **Do not read or write another agent's config** (`.codex/`, `.gemini/`, `.copilot/`,
  `.aider*`) as part of a task here.
- **Never edit this file to add a project rule.** Project rules go in `AGENTS.md` so every
  tool sees them. Two copies of the same guidance drift — that is why this file was cut
  down on 2026-09-21.
