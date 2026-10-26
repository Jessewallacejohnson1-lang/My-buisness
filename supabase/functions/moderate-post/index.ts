import { createClient } from "npm:@supabase/supabase-js@2"
// Supabase Edge Function: moderate a community post with Claude (text + image).
// Deploy: supabase functions deploy moderate-post
// Secret: supabase secrets set ANTHROPIC_API_KEY=...
//
// The caller's JWT is verified here as well as by `verify_jwt`: this function
// spends Anthropic credits per call, so an unauthenticated request must not
// reach the model. That check was added to the deployed copy and never landed
// in this repo until 2026-09-21 — the repo's version had no auth at all.
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const SYSTEM = `You moderate posts for Block Party, a warm, calm, hyper-local community app for the real town of St. Joseph, Minnesota. Neighbors post events, clubs, and trails.

Approve when the post is a plausible local community post of its stated kind, is not spam/advertising/scam, is not abusive/hateful/harassing, and is not sexual, violent, or otherwise inappropriate. If an image is provided it must also be appropriate. Minor unpolished wording is fine — do not reject for tone alone.

Reject only with a clear, kind, specific reason the poster can act on.

Respond with ONLY a JSON object: {"ok": true|false, "reason": "<short reason; empty when ok>"}`

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), { status, headers: { ...CORS, 'Content-Type': 'application/json' } })

  const key = Deno.env.get('ANTHROPIC_API_KEY')
  if (!key) return json({ ok: false, reason: 'Moderation unavailable.' }, 503)

  const auth = req.headers.get('Authorization') ?? ''
  const token = auth.startsWith('Bearer ') ? auth.slice(7) : ''
  if (!token) return json({ ok: false, reason: 'Unauthorized.' }, 401)
  try {
    const publishableKeys = JSON.parse(Deno.env.get('SUPABASE_PUBLISHABLE_KEYS') ?? '{}')
    const supabase = createClient(Deno.env.get('SUPABASE_URL')!, publishableKeys['default'])
    const { data: claimsData, error: claimsError } = await supabase.auth.getClaims(token)
    if (claimsError || !claimsData?.claims?.sub) return json({ ok: false, reason: 'Unauthorized.' }, 401)
    // An anonymous account (every install's quiet account, 2026-10-09) can't publish,
    // so it never needs a check and must not be able to spend credits on one.
    if (claimsData.claims.is_anonymous === true) return json({ ok: false, reason: 'Sign in to post.' }, 403)
  } catch {
    return json({ ok: false, reason: 'Unauthorized.' }, 401)
  }

  let body: any
  try { body = await req.json() } catch { return json({ ok: false, reason: 'Bad request.' }, 400) }

  // A reported neighbour posting, read again (BP app town-feed 22). The posting is read here, never
  // taken from the caller; claim_recheck lets each one through once, so a second report or a retry
  // never pays again. A "breaks the rules" answer declines it as reported: it leaves every feed.
  let admin: any = null
  if (body.recheck) {
    admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!)
    const { data: claimed, error } = await admin.rpc('claim_recheck', { p_event: body.recheck })
    if (error) return json({ ok: false, reason: 'Could not auto-check.' }, 502)
    if (!claimed) return json({ ok: true, reason: '' })
    const { data: e } = await admin.from('club_events')
      .select('id, kind, title, location, description, image_url').eq('id', body.recheck).single()
    if (!e) return json({ ok: true, reason: '' })
    body = { recheck: e.id, kind: e.kind, title: e.title, location: e.location, description: e.description,
             image_url: e.image_url }
  }

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
    if (admin && !parsed.ok) {
      await admin.from('club_events').update({ status: 'rejected', review_reason: 'reported' }).eq('id', body.recheck)
    }
    return json({ ok: !!parsed.ok, reason: parsed.reason ?? '' })
  } catch {
    return json({ ok: false, reason: 'Could not auto-check.' }, 502)
  }
})
