// prompt-sync.check.mts — guard against the failure mode that shipped a wrong line:
// prompts/almanac.md and the ALMANAC_PROMPT_B64 blob embedded in index.ts drifting apart.
//
// WHY THIS EXISTS: the Management API deploy bundles only the .ts files. prompts/almanac.md
// does NOT ship — not even with `static_patterns` set (verified against the live v3/v4
// ESZIP). So in production `Deno.readTextFile("./prompts/almanac.md")` always throws and the
// embedded base64 copy is the prompt that actually runs. Editing the .md alone changes
// nothing in prod, silently, with no error anywhere.
//
// Run standalone:  node prompt-sync.check.mts     (exit 1 on drift)
// Also runs automatically at the top of verify.mts.
import { readFileSync } from "node:fs"
import { fileURLToPath } from "node:url"
import { dirname, join } from "node:path"

const HERE = dirname(fileURLToPath(import.meta.url))

export interface PromptSyncResult {
  ok: boolean
  message: string
}

/** Decode the blob embedded in index.ts and compare it to prompts/almanac.md. */
export function checkPromptSync(): PromptSyncResult {
  const md = readFileSync(join(HERE, "prompts/almanac.md"), "utf8")
  const index = readFileSync(join(HERE, "index.ts"), "utf8")

  const match = index.match(/const ALMANAC_PROMPT_B64 =\s*"([A-Za-z0-9+/=]+)"/)
  if (!match) {
    return {
      ok: false,
      message:
        "ALMANAC_PROMPT_B64 not found in index.ts.\n" +
        "  Production has NO prompt then — prompts/almanac.md does not ship with the deploy,\n" +
        "  so the function would fall open to {\"line\":null} for every uncached user.\n" +
        "  Restore the embedded fallback before deploying.",
    }
  }

  let embedded: string
  try {
    embedded = Buffer.from(match[1], "base64").toString("utf8")
  } catch {
    return { ok: false, message: "ALMANAC_PROMPT_B64 is not valid base64." }
  }

  if (embedded === md) {
    return { ok: true, message: `embedded prompt matches prompts/almanac.md (${md.length} chars)` }
  }

  return { ok: false, message: describeDrift(md, embedded) }
}

/** Point at the first difference so the fix is obvious, not a wall of text. */
function describeDrift(md: string, embedded: string): string {
  const a = md.split("\n")
  const b = embedded.split("\n")
  const lines: string[] = [
    "prompts/almanac.md and the embedded ALMANAC_PROMPT_B64 have DRIFTED.",
    `  file: ${md.length} chars / ${a.length} lines`,
    `  blob: ${embedded.length} chars / ${b.length} lines`,
  ]
  for (let i = 0; i < Math.max(a.length, b.length); i++) {
    if (a[i] !== b[i]) {
      lines.push(`  first difference at line ${i + 1}:`)
      lines.push(`    file: ${a[i] ?? "(missing)"}`)
      lines.push(`    blob: ${b[i] ?? "(missing)"}`)
      break
    }
  }
  lines.push("")
  lines.push("  The blob is what actually runs in production. Regenerate it:")
  lines.push("    base64 -i prompts/almanac.md")
  lines.push("  then replace the ALMANAC_PROMPT_B64 string literal in index.ts.")
  return lines.join("\n")
}

/** Throw on drift — used by verify.mts so a stale blob can't slip through a verify run. */
export function assertPromptSync(): void {
  const res = checkPromptSync()
  if (!res.ok) throw new Error(`[prompt-sync] ${res.message}`)
}

// Standalone invocation: `node prompt-sync.check.mts`
if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const res = checkPromptSync()
  console.log(`prompt-sync: ${res.ok ? "PASS" : "FAIL"} — ${res.message}`)
  if (!res.ok) process.exit(1)
}
