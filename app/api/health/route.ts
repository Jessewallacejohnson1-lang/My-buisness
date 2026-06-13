import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'

/**
 * Diagnostic checklist for "why isn't the app working" — backend setup is the
 * usual culprit. Reports which required tables/columns exist and which env vars
 * are present (booleans only — never the values). Hit GET /api/health anytime.
 */
export async function GET() {
  const checks: { name: string; ok: boolean; detail?: string }[] = []

  // Env presence (booleans only).
  const env: [string, boolean][] = [
    ['NEXT_PUBLIC_SUPABASE_URL', !!process.env.NEXT_PUBLIC_SUPABASE_URL],
    ['NEXT_PUBLIC_SUPABASE_ANON_KEY', !!process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY],
    ['ANTHROPIC_API_KEY (photo scan)', !!process.env.ANTHROPIC_API_KEY],
  ]
  for (const [name, ok] of env) checks.push({ name: `env: ${name}`, ok })

  // Schema: select one of each required column; a 42703 means the migration
  // wasn't (re-)run. We only read metadata, never user rows.
  const supabase = await createClient()
  const probes: [string, string, string][] = [
    ['profiles table', 'profiles', 'user_id'],
    ['profiles.focus column', 'profiles', 'focus'],
    ['food_logs.user_id column', 'food_logs', 'user_id'],
    ['workouts.user_id column', 'workouts', 'user_id'],
  ]
  for (const [name, table, column] of probes) {
    const { error } = await supabase.from(table).select(column).limit(1)
    checks.push({
      name: `db: ${name}`,
      ok: !error,
      detail: error?.message,
    })
  }

  const healthy = checks.every((c) => c.ok)
  return NextResponse.json(
    {
      healthy,
      summary: healthy
        ? 'All required tables, columns, and env vars are present.'
        : 'Setup incomplete — see the failing checks below.',
      checks,
    },
    { status: healthy ? 200 : 503 }
  )
}
