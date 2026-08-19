// Supabase Edge Function: log-agent-event — Control Room · Panel 3.
//
// Receives ONE Claude Code hook event (from .claude/hooks/log-event.sh in the
// app repos) and inserts it into public.agent_events. Callers authenticate
// with the project's PUBLIC anon key (a valid project JWT — verify_jwt stays
// on); the insert itself runs with the service credentials, and this
// function's code scopes that power to exactly one table.
//
// Deploy: supabase functions deploy log-agent-event

const SUMMARY_MAX = 500
const FIELD_MAX = 400
const RAW_MAX_CHARS = 20_000

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405)
  try {
    const supaUrl = Deno.env.get("SUPABASE_URL")
    const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}")
    const serviceKey = secretKeys["default"]
    if (!supaUrl || !serviceKey) return json({ error: "misconfigured" }, 500)

    const body = (await req.json().catch(() => null)) as Record<string, unknown> | null
    if (body === null || typeof body !== "object") return json({ error: "bad json" }, 400)

    const event = str(body.event)
    if (event === null) return json({ error: "event is required" }, 400)

    const row = {
      session_id: str(body.session_id),
      prompt_id: str(body.prompt_id),
      event,
      tool_name: str(body.tool_name),
      repo: str(body.repo),
      branch: str(body.branch),
      file_path: str(body.file_path),
      summary: str(body.summary, SUMMARY_MAX),
      raw: capRaw(body.raw ?? {}),
    }

    const res = await fetch(`${supaUrl}/rest/v1/agent_events`, {
      method: "POST",
      headers: {
        apikey: serviceKey,
        Authorization: `Bearer ${serviceKey}`,
        "Content-Type": "application/json",
        Prefer: "return=minimal",
      },
      body: JSON.stringify(row),
    })
    if (!res.ok) {
      console.error(`[log-agent-event] insert failed: ${res.status} ${await res.text()}`)
      return json({ error: `insert failed: ${res.status}` }, 502)
    }
    return new Response(null, { status: 204 })
  } catch (cause) {
    console.error("[log-agent-event] unexpected:", cause)
    return json({ error: "unexpected" }, 500)
  }
})

function str(v: unknown, max = FIELD_MAX): string | null {
  return typeof v === "string" && v.length > 0 ? v.slice(0, max) : null
}

/** raw can carry whole file contents via tool_input — cap it hard. */
function capRaw(raw: unknown): unknown {
  const text = JSON.stringify(raw ?? {})
  return text.length <= RAW_MAX_CHARS ? raw : { truncated: true, head: text.slice(0, RAW_MAX_CHARS) }
}

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  })
}
