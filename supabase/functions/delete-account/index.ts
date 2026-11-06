import { createClient } from "npm:@supabase/supabase-js@2"
// Supabase Edge Function: a person deletes their own account from Settings (BP app docs/plans/launch-ready, ticket 01;
// Apple 5.1.1(v)). The token says who; nothing in the request does.
// Deploy: supabase functions deploy delete-account
//
// Rows, then files, then the account, so a failure leaves a person who can still sign in and try again, and the retry
// finishes the job. `public.delete_my_account` stays for "Come back when you're 13", which has no posts or files yet.

// Every bucket a person's own files sit in, each under a folder named by their id. SQL deletes on storage.objects are
// refused, and only the service key can remove from `avatars` and `chat-photos`.
const BUCKETS = ['avatars', 'event-images', 'chat-photos']
const PAGE = 100

Deno.serve(async (req) => {
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })

  const auth = req.headers.get('Authorization') ?? ''
  const token = auth.startsWith('Bearer ') ? auth.slice(7) : ''
  if (!token) return json({ ok: false }, 401)
  let caller = ''
  try {
    const publishableKeys = JSON.parse(Deno.env.get('SUPABASE_PUBLISHABLE_KEYS') ?? '{}')
    const supabase = createClient(Deno.env.get('SUPABASE_URL')!, publishableKeys['default'])
    const { data, error } = await supabase.auth.getClaims(token)
    if (error || !data?.claims?.sub) return json({ ok: false }, 401)
    caller = String(data.claims.sub)
  } catch {
    return json({ ok: false }, 401)
  }

  const admin = createClient(Deno.env.get('SUPABASE_URL')!, JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') ?? '{}')['default'])

  const { data: keep, error: rows } = await admin.rpc('clear_account_rows', { p_user: caller })
  if (rows) {
    console.error('delete-account: rows failed', rows.code)
    return json({ ok: false }, 502)
  }
  const kept = new Set<string>(keep ?? [])

  // A list returns one page, so this lists until nothing's left but what stays. A file named in an open chat report
  // stays in the list, so the next page starts past those.
  const emptyFolder = async (bucket: string) => {
    const files = admin.storage.from(bucket)
    let offset = 0
    while (true) {
      const { data: page, error } = await files.list(caller, { limit: PAGE, offset })
      if (error) throw error
      if (!page?.length) return
      const paths = page.map((f) => `${caller}/${f.name}`).filter((path) => !kept.has(path))
      if (paths.length) {
        const { data: removed, error: failed } = await files.remove(paths)
        if (failed) throw failed
        if (!removed?.length) throw new Error('nothing removed')
      }
      offset += page.length - paths.length
    }
  }
  try {
    for (const bucket of BUCKETS) await emptyFolder(bucket)
  } catch (err) {
    console.error('delete-account: files failed', String(err).slice(0, 120))
    return json({ ok: false }, 502)
  }

  // A 404 is a retry after a reply that got lost: the account already went, which is what they asked for.
  const { error: gone } = await admin.auth.admin.deleteUser(caller)
  if (gone && gone.status !== 404) {
    console.error('delete-account: account failed', gone.status)
    return json({ ok: false }, 502)
  }
  return json({ ok: true })
})
