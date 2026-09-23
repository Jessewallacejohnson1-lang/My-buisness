# CLAUDE.md

**`AGENTS.md` is the router for this repository.** Build commands, architecture, the
design system and the trap list are reached from its trigger table. This file only loads
it and holds the notes that apply to Claude Code and to no other agent.

The router loads with this line:

@AGENTS.md

Jesse's standing corrections load with this one:

@MEMORY.md

Precedence when sources disagree: **the code wins, then `MEMORY.md`, then `AGENTS.md`,
then this file.** Surface the mismatch rather than inventing a path or an API around it.

## Claude-only notes

- **Tooling is not guaranteed.** `[prose]` Every tool below is optional. Use it only if it
  is actually present in this session — XcodeBuildMCP, graphify, code-review-graph alike;
  otherwise take the fallback named in the leaf file.
- **Prefer XcodeBuildMCP** (`build_run_sim`, `build_sim`, `screenshot`) over raw shell for
  Apple tooling. `[prose]` The raw `xcodebuild` / `xcrun simctl` fallbacks are in
  `docs/rules/build.md`. Run `session_show_defaults` **before** a build: every worktree
  builds the same bundle id, so installing any of them overwrites the same simulator app
  and the last build wins.
- **Use `graphify` first for codebase questions** when `graphify-out/graph.json` exists.
  `[prose]` `graphify query "<q>"`, `graphify path "<A>" "<B>"`, `graphify explain
  "<concept>"` return a scoped subgraph far smaller than `GRAPH_REPORT.md` or raw grep;
  `graphify-out/wiki/index.md` is for broad navigation and `GRAPH_REPORT.md` only for a
  whole-architecture review. Run `graphify update .` after modifying code.
- **Do not read or write another agent's config** (`.codex/`, `.gemini/`, `.copilot/`,
  `.aider*`) as part of a task here. `[prose]`

**This file is generated.** `[ci]` Edit `rules/claude/*.md`, then
`python3 scripts/bp_rules.py build`. Project rules go in `rules/router/` or a leaf, never
here — two copies of the same guidance drift.
