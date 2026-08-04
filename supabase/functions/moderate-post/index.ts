// Supabase Edge Function: moderate a community post with Claude (text + image).
// Deploy: supabase functions deploy moderate-post
// Secret: supabase secrets set ANTHROPIC_API_KEY=...
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const SYSTEM = `You moderate posts for Hygge, a warm, calm, hyper-local community app for the real town of St. Joseph, Minnesota. Neighbors post events, clubs, and trails.

Approve when the post is a plausible local community post of its stated kind, is not spam/advertising/scam, is not abusive/hateful/harassing, and is not sexual, violent, or otherwise inappropriate. If an image is provided it must also be appropriate. Minor unpolished wording is fine — do not reject for tone alone.

Reject only with a clear, kind, specific reason the poster can act on.

Respond with ONLY a JSON object: {"ok": true|false, "reason": "<short reason; empty when ok>"}`

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), { status, headers: { ...CORS, 'Content-Type': 'application/json' } })

  const key = Deno.env.get('ANTHROPIC_API_KEY')
  if (!key) return json({ ok: false, reason: 'Moderation unavailable.' }, 503)

  let body: any
  try { body = await req.json() } catch { return json({ ok: false, reason: 'Bad request.' }, 400) }

  const facts = [
    `Kind: ${body.kind}`,
    `Title: ${body.title}`,
    body.location ? `Location: ${body.location}` : null,
    body.length ? `Length: ${body.length}` : null,
    body.description ? `Description: ${body.description}` : null,
  ].filter(Boolean).join('\n')

  const content: any[] = [{ type: 'text', text: facts }]
  if (body.image_url) content.push({ type: 'image', source: { type: 'url', url: body.image_url } })

  try {
    const res = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: { 'x-api-key': key, 'anthropic-version': '2023-06-01', 'content-type': 'application/json' },
      body: JSON.stringify({
        model: 'claude-haiku-4-5-20251001',
        max_tokens: 200,
        system: SYSTEM,
        messages: [{ role: 'user', content }],
      }),
    })
    if (!res.ok) return json({ ok: false, reason: 'Could not auto-check.' }, 502)
    const data = await res.json()
    const text = (data.content ?? []).filter((b: any) => b.type === 'text').map((b: any) => b.text).join('').trim()
    const match = text.match(/\{[\s\S]*\}/)
    if (!match) return json({ ok: false, reason: 'Could not auto-check.' }, 502)
    const parsed = JSON.parse(match[0])
    return json({ ok: !!parsed.ok, reason: parsed.reason ?? '' })
  } catch {
    return json({ ok: false, reason: 'Could not auto-check.' }, 502)
  }
})
