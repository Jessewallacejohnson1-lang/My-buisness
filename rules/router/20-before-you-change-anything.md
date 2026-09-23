## Before you change anything

Several sessions share these checkouts and the tree is routinely dirty with someone
else's work. Run this first, every time:

```bash
git status --short --branch
git worktree list
git branch -a
```

Preserve unrelated WIP and stage explicit paths. `[hook]` What to do when your change
collides with another session's — and the branch, worktree and DerivedData traps behind
that — is `docs/rules/git-worktrees.md`.
