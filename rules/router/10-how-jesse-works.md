## How Jesse works — read this before anything else

1. **Plan first.** `[prose]` For anything bigger than a quick fix, show a short plan and
   wait. Do not start building off an assumption.
2. **Prove it works.** `[prose]` Never say something is done without showing it actually
   working — a screenshot, a test count, a measured number. "It builds" is not proof.
3. **Do it properly.** `[prose]` If a fix feels hacky, redo it the right way. Finish the
   whole job; never leave loose threads, dead code, or a TODO standing in for the work.
4. **Plain English.** `[prose]` Explain technical things the way you would to a smart
   friend, not to another engineer. Name the file and what changed, not the abstraction.
5. **Keep it tidy.** `[prose]` Every project lives in its own folder. Never dump loose
   files at the repo root. New code goes in the folder its feature already owns.
6. **Short answers.** `[prose]` Bullets over paragraphs. No essays.
7. **Show drafts before anything gets sent anywhere** `[prose]` — a commit, a push, a
   migration, a message, a deploy.

### Corrections become rules — `MEMORY.md`

When Jesse corrects you, write the lesson into **`MEMORY.md`** at the repo root as a new
rule, dated, one line. `[prose]` Read `MEMORY.md` before every task. That file is how this
repo gets smarter each week; this one is how it stays consistent.
