import { createClient } from "npm:@supabase/supabase-js@2"
// Supabase Edge Function: Claude's instant check (text + image) on a neighbour's new Event from
// New event (`submit`, BP app references/town-plus), on an edit of a live post (`edit`, BP app town-feed 44), and on a reported posting read again
// (`recheck`, BP app town-feed 22).
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

const SYSTEM = `You moderate posts for Block Party, a warm, calm, hyper-local community app for the real town of St. Joseph, Minnesota. Neighbors post events, clubs, and trails, and everyday posts (kind "post"): a few words about life around town, maybe with a photo, with no date; a photo with no words is fine.

Approve when the post is a plausible local community post of its stated kind, is not spam/advertising/scam, is not abusive/hateful/harassing, and is not sexual, violent, or otherwise inappropriate. If an image is provided it must also be appropriate. A photo from another day, angle or place is fine: never turn a post down because its photo doesn't match its name or its place. An everyday post's words, Location and photo needn't match each other either: someone at a brewery may write about sledding. Minor unpolished wording is fine — do not reject for tone alone.

Reject only with a clear, kind, specific reason the poster can act on, in one short sentence.

Respond with ONLY a JSON object: {"ok": true|false, "reason": "<short reason; empty when ok>"}`

// A neighbour's note on a "Wrong info" report (BP app backlog 26): only Block Party's admin reads it, to fix the Event.
const NOTE_RULE = `You read short notes neighbors add when they report that an Event on Block Party, a warm, calm, hyper-local community app for the real town of St. Joseph, Minnesota, has wrong information: its time, day, place, or that it was called off. Only Block Party's admin reads these notes.

Reject a note that is abusive, hateful, harassing, threatening, sexual, spam or advertising, or that gives a person's private details (a phone number, a home address, an email). Approve every other note, even when it is short, blunt, misspelled or off topic.

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
  let caller = ''
  try {
    const publishableKeys = JSON.parse(Deno.env.get('SUPABASE_PUBLISHABLE_KEYS') ?? '{}')
    const supabase = createClient(Deno.env.get('SUPABASE_URL')!, publishableKeys['default'])
    const { data: claimsData, error: claimsError } = await supabase.auth.getClaims(token)
    if (claimsError || !claimsData?.claims?.sub) return json({ ok: false, reason: 'Unauthorized.' }, 401)
    // An anonymous account (every install's quiet account, 2026-10-09) can't publish,
    // so it never needs a check and must not be able to spend credits on one.
    if (claimsData.claims.is_anonymous === true) return json({ ok: false, reason: 'Sign in to post.' }, 403)
    caller = String(claimsData.claims.sub)
  } catch {
    return json({ ok: false, reason: 'Unauthorized.' }, 401)
  }

  let body: any
  try { body = await req.json() } catch { return json({ ok: false, reason: 'Bad request.' }, 400) }

  const admin = createClient(Deno.env.get('SUPABASE_URL')!, JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') ?? '{}')['default'])

  // The model's yes or no on one posting, or on a report's note about it, read here and never taken from
  // the caller; null when it gave no answer.
  const verdict = async (e: any, note?: string): Promise<{ ok: boolean, reason: string } | null> => {
    const facts = note !== undefined ? `Event: ${e.title}\nNote: ${note}` : [
      `Kind: ${e.kind}`,
      e.kind === 'post' ? `Words: ${e.title || '(none, just the photo)'}` : `Title: ${e.title}`,
      e.event_date ? `When: ${e.event_date}${e.start_time ? ` ${e.start_time}` : ''}` : null,
      e.location ? `Location: ${[e.location, ...(e.more_places ?? [])].join('; ')}` : null,
      e.description ? `Description: ${e.description}` : null,
    ].filter(Boolean).join('\n')
    const content: any[] = [{ type: 'text', text: facts }]
    if (e.image_url && note === undefined) content.push({ type: 'image', source: { type: 'url', url: e.image_url } })
    try {
      const res = await fetch('https://api.anthropic.com/v1/messages', {
        method: 'POST',
        headers: { 'x-api-key': key, 'anthropic-version': '2023-06-01', 'content-type': 'application/json' },
        body: JSON.stringify({
          // Haiku 5.5 at low effort: 30 of 30 on BP app check-cost 02's test, three times, where
          // Haiku 4.5 got 20 or 21, at about a sixth of the cost. Its thinking counts toward max_tokens.
          model: 'claude-haiku-5-5',
          max_tokens: 1024,
          output_config: { effort: 'low' },
          system: note === undefined ? SYSTEM : NOTE_RULE,
          messages: [{ role: 'user', content }],
        }),
      })
      // Why the check couldn't answer, for the function's logs; never the caller's words.
      if (!res.ok) { console.error('moderate-post: model answered', res.status, (await res.text()).slice(0, 300)); return null }
      const data = await res.json()
      // What each check cost, in tokens, for the function's logs (BP app check-cost).
      console.log('moderate-post: usage', JSON.stringify(data.usage))
      // A safety decline (Haiku 5.5 has no fallback model) or a cut-off answer is no answer.
      if (data.stop_reason !== 'end_turn') { console.error('moderate-post: stopped', data.stop_reason, data.stop_details?.category ?? ''); return null }
      const text = (data.content ?? []).filter((b: any) => b.type === 'text').map((b: any) => b.text).join('').trim()
      const match = text.match(/\{[\s\S]*\}/)
      if (!match) { console.error('moderate-post: no JSON in', text.slice(0, 200)); return null }
      const parsed = JSON.parse(match[0])
      return { ok: !!parsed.ok, reason: String(parsed.reason ?? '') }
    } catch (err) {
      console.error('moderate-post: model call failed', String(err).slice(0, 200))
      return null
    }
  }

  // A neighbour's own new Event or post (BP app references/town-plus, references/post-screen). claim_submit lets it through once,
  // only while it's the caller's, pending, plain (nothing set the check doesn't read) and one of
  // their 10 that day. Yes puts it live; no declines it and takes its photo down; no answer leaves
  // it pending and claimed, so it waits for Jesse's Review and never pays twice. Nothing claimed
  // (sent twice, the day's 10 used) is a 429 the app reads as waiting.
  if (body?.submit) {
    const id = String(body.submit)
    const { data: claimed, error } = await admin.rpc('claim_submit', { p_event: id, p_user: caller })
    if (error) return json({ ok: false, reason: 'Could not auto-check.' }, 502)
    if (!claimed) return json({ ok: false, reason: 'Not checked.' }, 429)
    const { data: e } = await admin.from('club_events')
      .select('id, kind, title, event_date, start_time, location, more_places, description, image_url').eq('id', id).single()
    if (!e) return json({ ok: false, reason: 'Could not auto-check.' }, 502)
    const said = await verdict(e)
    if (!said) return json({ ok: false, reason: 'Could not auto-check.' }, 502)
    if (said.ok) {
      const { error: up } = await admin.from('club_events').update({ status: 'approved' }).eq('id', id).eq('status', 'pending')
      return up ? json({ ok: false, reason: 'Could not auto-check.' }, 502) : json({ ok: true, reason: '' })
    }
    await admin.from('club_events').update({ status: 'rejected', review_reason: 'declined' }).eq('id', id)
    const photo = typeof e.image_url === 'string' ? e.image_url.split('/event-images/')[1] : undefined
    if (photo) await admin.storage.from('event-images').remove([photo])
    return json({ ok: false, reason: said.reason })
  }

  // A neighbour's edit of their own live post (BP app town-feed 44): new words and Place, read with the post's own photo.
  // claim_edit lets it through only on the caller's live post, 10 a day; nothing is written until the model says yes, so
  // a no or no answer leaves the post as it was (and, unlike `submit`, never takes its photo down). A yes writes the
  // words, the Place and the kept @ names alone (apply_post_edit). 'limit' is a 429 the app reads as the day's 10; a post
  // gone while it was checked, a 410.
  if (body?.edit) {
    const id = String(body.edit)
    const words = typeof body.words === 'string' ? body.words : ''
    const place = typeof body.place === 'string' ? body.place.trim() : ''
    const names = Array.isArray(body.names) ? body.names : null
    const { data: claimed, error } = await admin.rpc('claim_edit', { p_event: id, p_user: caller, p_words: words, p_place: place })
    if (error) return json({ ok: false, reason: 'Could not auto-check.' }, 502)
    if (claimed === 'limit') return json({ ok: false, reason: 'Not checked.' }, 429)
    if (claimed !== 'claimed') return json({ ok: false, reason: 'Not checked.' }, 403)
    const { data: e } = await admin.from('club_events').select('image_url').eq('id', id).single()
    if (!e) return json({ ok: false, reason: 'Gone.' }, 410)
    const said = await verdict({ kind: 'post', title: words, location: place || null, image_url: e.image_url })
    if (!said) return json({ ok: false, reason: 'Could not auto-check.' }, 502)
    if (!said.ok) return json({ ok: false, reason: said.reason })
    const { data: applied, error: up } = await admin.rpc('apply_post_edit',
      { p_event: id, p_user: caller, p_words: words, p_place: place, p_names: names })
    if (up) return json({ ok: false, reason: 'Could not auto-check.' }, 502)
    return applied ? json({ ok: true, reason: '' }) : json({ ok: false, reason: 'Gone.' }, 410)
  }

  // A reported neighbour posting, read again (BP app town-feed 22): a caller's own text let any
  // signed-in account spend credits without end (BP app loopholes 04). claim_recheck lets each one
  // through once, so a second report or a retry never pays again. A "breaks the rules" answer
  // declines it as reported: it leaves every feed.
  // A "Wrong info" report's notes (BP app backlog 26), read before the admin sees them. claim_notes lets each note
  // through once, so a retry or a second report never pays again; a yes keeps the note, a no or no answer clears it
  // and the report stays. The Review queue shows only kept notes.
  if (body?.note) {
    const id = String(body.note)
    const { data: notes, error } = await admin.rpc('claim_notes', { p_event: id })
    if (error) return json({ ok: false, reason: 'Could not auto-check.' }, 502)
    if (!notes?.length) return json({ ok: true, reason: '' })
    const { data: e } = await admin.from('club_events').select('title').eq('id', id).single()
    for (const n of notes) {
      const said = e ? await verdict(e, String(n.note)) : null
      await admin.from('reports').update(said?.ok ? { note_ok: true } : { note: null, note_ok: null }).eq('id', n.id)
    }
    return json({ ok: true, reason: '' })
  }

  if (!body?.recheck) return json({ ok: false, reason: 'Bad request.' }, 400)
  // A re-check the model never answered goes back unclaimed, so the next report tries again.
  const unclaim = () => admin.from('club_events').update({ rechecked_at: null }).eq('id', body.recheck)
  const { data: claimed, error } = await admin.rpc('claim_recheck', { p_event: body.recheck })
  if (error) return json({ ok: false, reason: 'Could not auto-check.' }, 502)
  if (!claimed) return json({ ok: true, reason: '' })
  const { data: e } = await admin.from('club_events')
    .select('id, kind, title, location, more_places, description, image_url').eq('id', body.recheck).single()
  if (!e) return json({ ok: true, reason: '' })
  const said = await verdict(e)
  if (!said) { await unclaim(); return json({ ok: false, reason: 'Could not auto-check.' }, 502) }
  if (!said.ok) {
    await admin.from('club_events').update({ status: 'rejected', review_reason: 'reported' }).eq('id', body.recheck)
  }
  return json(said)
})
