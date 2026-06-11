'use client'

import Link from 'next/link'
import { Suspense, useState } from 'react'
import { useRouter, useSearchParams } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'

type Mode = 'signin' | 'signup'

function LoginForm() {
  const router = useRouter()
  const searchParams = useSearchParams()
  const next = searchParams.get('next') ?? '/dashboard'
  const linkError = searchParams.get('error') === 'link'

  const [mode, setMode] = useState<Mode>('signin')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(
    linkError ? 'That sign-in link expired. Enter your details to continue.' : null
  )
  const [checkEmail, setCheckEmail] = useState(false)

  const submit = async (e: React.FormEvent) => {
    e.preventDefault()
    setBusy(true)
    setError(null)
    const supabase = createClient()

    try {
      if (mode === 'signup') {
        const { data, error } = await supabase.auth.signUp({
          email,
          password,
          options: { emailRedirectTo: `${location.origin}/auth/callback` },
        })
        if (error) throw error
        if (data.session) {
          router.push(next)
          router.refresh()
        } else {
          setCheckEmail(true)
        }
      } else {
        const { error } = await supabase.auth.signInWithPassword({ email, password })
        if (error) throw error
        router.push(next)
        router.refresh()
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Something went wrong. Try again.')
    } finally {
      setBusy(false)
    }
  }

  if (checkEmail) {
    return (
      <div className="text-center rise">
        <div className="mx-auto mb-6 w-14 h-14 rounded-full border border-moss-500/40 bg-moss-500/10 flex items-center justify-center">
          <svg viewBox="0 0 24 24" className="w-6 h-6 text-moss-300" fill="none" stroke="currentColor" strokeWidth="1.5">
            <rect x="3" y="5" width="18" height="14" rx="2" />
            <path d="M3 7l9 6 9-6" />
          </svg>
        </div>
        <h1 className="font-display text-2xl text-cream mb-2">Check your email</h1>
        <p className="text-fog text-sm leading-relaxed max-w-xs mx-auto">
          We sent a confirmation link to <span className="text-cream">{email}</span>.
          Open it on this device to start tracking.
        </p>
      </div>
    )
  }

  return (
    <div className="w-full max-w-sm rise">
      <div className="text-center mb-8">
        <Link href="/" className="font-display text-cream text-2xl tracking-[0.25em] uppercase">
          Grove
        </Link>
        <p className="text-fog text-sm mt-3">
          {mode === 'signin' ? 'Welcome back. Pick up the streak.' : 'Start your first ring today.'}
        </p>
      </div>

      <form onSubmit={submit} className="space-y-3">
        <label className="block">
          <span className="sr-only">Email</span>
          <input
            type="email"
            required
            autoComplete="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            placeholder="Email"
            className="w-full bg-bark-800 border border-white/[0.07] rounded-xl px-4 py-3.5 text-sm text-cream placeholder:text-fog-dim focus:border-moss-500/50 focus:outline-none transition-colors"
          />
        </label>
        <label className="block">
          <span className="sr-only">Password</span>
          <input
            type="password"
            required
            minLength={6}
            autoComplete={mode === 'signin' ? 'current-password' : 'new-password'}
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            placeholder={mode === 'signin' ? 'Password' : 'Password (6+ characters)'}
            className="w-full bg-bark-800 border border-white/[0.07] rounded-xl px-4 py-3.5 text-sm text-cream placeholder:text-fog-dim focus:border-moss-500/50 focus:outline-none transition-colors"
          />
        </label>

        {error && (
          <p className="text-clay-300 text-xs leading-relaxed px-1" role="alert">
            {error}
          </p>
        )}

        <button
          type="submit"
          disabled={busy}
          className="w-full bg-moss-400 hover:bg-moss-300 text-bark-950 font-semibold py-3.5 rounded-xl text-sm transition-colors disabled:opacity-60"
        >
          {busy ? 'One moment…' : mode === 'signin' ? 'Sign in' : 'Create account'}
        </button>
      </form>

      <button
        onClick={() => {
          setMode(mode === 'signin' ? 'signup' : 'signin')
          setError(null)
        }}
        className="block mx-auto mt-6 text-sm text-fog hover:text-cream transition-colors"
      >
        {mode === 'signin' ? 'New here? Create an account' : 'Already tracking? Sign in'}
      </button>
    </div>
  )
}

export default function LoginPage() {
  return (
    <div className="min-h-screen relative flex items-center justify-center px-6 py-16">
      {/* growth rings ornament */}
      <div
        aria-hidden
        className="absolute inset-0 pointer-events-none"
        style={{
          background:
            'repeating-radial-gradient(circle at 50% 120%, transparent 0px, transparent 79px, rgba(164,193,143,0.05) 80px, transparent 81px)',
        }}
      />
      <Suspense>
        <LoginForm />
      </Suspense>
    </div>
  )
}
