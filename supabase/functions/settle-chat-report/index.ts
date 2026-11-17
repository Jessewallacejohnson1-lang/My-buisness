import { createClient } from "npm:@supabase/supabase-js@2"
// Supabase Edge Function: the admin settles a chat report from the Review queue (BP app five-tabs 09). The database's
// resolve_chat_report checks the caller is an admin and settles it; when the report's photo belongs to a deleted account
// and no other open report names it, it answers with that photo's path, and this removes the file. Only the service key
// can remove from `chat-photos`. Body: { report: uuid, hide: boolean }.
// Deploy: supabase functions deploy settle-chat-report

Deno.serve(async (req) => {
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })

  const auth = req.headers.get('Authorization') ?? ''
  if (!auth.startsWith('Bearer ')) return json({ ok: false }, 401)
  let report = ''
  let hide = false
  try {
    const body = await req.json()
    report = String(body.report ?? '')
    hide = body.hide === true
  } catch {
    return json({ ok: false }, 400)
  }
  if (!/^[0-9a-f-]{36}$/i.test(report)) return json({ ok: false }, 400)

  // As the caller, so the database's own admin check decides.
  const publishableKeys = JSON.parse(Deno.env.get('SUPABASE_PUBLISHABLE_KEYS') ?? '{}')
  const caller = createClient(Deno.env.get('SUPABASE_URL')!, publishableKeys['default'], {
    global: { headers: { Authorization: auth } },
  })
  const { data: photo, error } = await caller.rpc('resolve_chat_report', { p_report: report, p_hide: hide })
  if (error) return json({ ok: false }, error.code === '42501' ? 403 : 502)

  // The report is settled either way; a file that fails to go is logged, and settling again retries it.
  if (typeof photo === 'string' && photo) {
    const admin = createClient(Deno.env.get('SUPABASE_URL')!, JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') ?? '{}')['default'])
    const { error: failed } = await admin.storage.from('chat-photos').remove([photo])
    if (failed) {
      console.error('settle-chat-report: photo failed', String(failed.message).slice(0, 120))
      return json({ ok: false }, 502)
    }
  }
  return json({ ok: true })
})
