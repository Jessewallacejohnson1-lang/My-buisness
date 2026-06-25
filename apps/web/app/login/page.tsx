'use client'

import Link from 'next/link'
import { Suspense, useState } from 'react'
import { useRouter, useSearchParams } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { haptic } from '@/lib/haptics'

type Mode = 'signin' | 'signup'

function LoginForm() {
  const router = useRouter()
  const searchParams = useSearchParams()
  const next = searchParams.get('next') ?? '/community'
  const linkError = searchParams.get('error') === 'link'

  const [mode, setMode] = useState<Mode>('signin')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(
    linkError ? 'That sign-in link expired. Enter your details to continue.' : null
  )
  const [checkEmail, setCheckEmail] = useState(false)
  const [unconfirmed, setUnconfirmed] = useState(false)

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
      const msg = err instanceof Error ? err.message : ''
      const m = msg.toLowerCase()
      if (m.includes('not confirmed') || m.includes('confirm')) {
        setUnconfirmed(true)
        setError("Your email isn't confirmed yet. Check your inbox for the link, or resend it below.")
      } else if (m.includes('invalid login') || m.includes('credentials')) {
        setError("That email or password doesn't match. Try again.")
      } else if (m.includes('already registered') || m.includes('already exists')) {
        setError('You already have an account with that email — switch to Sign in.')
      } else {
        setError(msg || 'Something went wrong. Try again.')
      }
    } finally {
      setBusy(false)
    }
  }

  const resendConfirmation = async () => {
    setBusy(true)
    setError(null)
    try {
      const supabase = createClient()
      const { error } = await supabase.auth.resend({
        type: 'signup',
        email,
        options: { emailRedirectTo: `${location.origin}/auth/callback` },
      })
      if (error) throw error
      setCheckEmail(true)
    } catch (err) {
      setError(err instanceof Error ? err.message : "Couldn't resend. Try again shortly.")
    } finally {
      setBusy(false)
    }
  }

  if (checkEmail) {
    return (
      <div className="text-center rise">
        <div
          className="mx-auto mb-6 w-16 h-16 rounded-full flex items-center justify-center"
          style={{
            background: 'color-mix(in srgb, var(--pine-700) 12%, transparent)',
            border: '1px solid color-mix(in srgb, var(--pine-700) 30%, transparent)',
          }}
        >
          <svg viewBox="0 0 24 24" className="w-7 h-7" fill="none" stroke="currentColor"
            strokeWidth={1.5} style={{ color: 'var(--pine-700)' }}>
            <rect x="3" y="5" width="18" height="14" rx="2" />
            <path d="M3 7l9 6 9-6" />
          </svg>
        </div>
        <h2 className="font-display text-2xl text-ink mb-2">Check your email</h2>
        <p className="text-sm leading-relaxed max-w-xs mx-auto" style={{ color: 'var(--char-400)' }}>
          We sent a link to <span className="text-ink font-medium">{email}</span>.
          Open it to step inside.
        </p>
      </div>
    )
  }

  return (
    <div className="w-full max-w-[360px] rise">
      {/* wordmark */}
      <div className="text-center mb-10">
        <Link href="/" className="inline-block mb-5">
          <span
            className="font-display tracking-[0.22em] uppercase"
            style={{ fontSize: '28px', color: 'var(--char-800)', letterSpacing: '0.22em' }}
          >
            HYGGE
          </span>
        </Link>
        <p className="font-display text-xl" style={{ color: 'var(--char-600)', fontStyle: 'italic' }}>
          {mode === 'signin' ? 'Welcome back.' : 'Find your people.'}
        </p>
        <p className="text-sm mt-1.5" style={{ color: 'var(--char-400)' }}>
          {mode === 'signin'
            ? 'Your neighborhood is waiting.'
            : 'Good people. Close by.'}
        </p>
      </div>

      <form onSubmit={submit} className="space-y-3">
        <input
          type="email"
          required
          autoComplete="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          placeholder="Email"
          className="w-full rounded-xl px-4 py-3.5 text-sm text-ink placeholder:text-ink-3 focus:outline-none transition-shadow"
          style={{
            background: 'rgba(255,255,255,0.72)',
            border: '1px solid rgba(0,0,0,0.10)',
            boxShadow: 'inset 0 1px 2px rgba(0,0,0,0.04)',
          }}
        />
        <input
          type="password"
          required
          minLength={6}
          autoComplete={mode === 'signin' ? 'current-password' : 'new-password'}
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          placeholder={mode === 'signin' ? 'Password' : 'Password (6+ characters)'}
          className="w-full rounded-xl px-4 py-3.5 text-sm text-ink placeholder:text-ink-3 focus:outline-none transition-shadow"
          style={{
            background: 'rgba(255,255,255,0.72)',
            border: '1px solid rgba(0,0,0,0.10)',
            boxShadow: 'inset 0 1px 2px rgba(0,0,0,0.04)',
          }}
        />

        {error && (
          <div role="alert" className="px-1">
            <p className="text-xs leading-relaxed" style={{ color: 'var(--clay-700)' }}>{error}</p>
            {unconfirmed && (
              <button
                type="button"
                onClick={resendConfirmation}
                disabled={busy}
                className="mt-1.5 text-xs underline underline-offset-2 transition-opacity disabled:opacity-50"
                style={{ color: 'var(--slate-600)' }}
              >
                Resend confirmation email
              </button>
            )}
          </div>
        )}

        <button
          type="submit"
          disabled={busy}
          onClick={() => haptic('tap')}
          className="press w-full font-medium py-3.5 rounded-xl text-sm transition-opacity disabled:opacity-60"
          style={{ background: 'var(--char-800)', color: 'var(--linen-50)' }}
        >
          {busy ? 'One moment…' : mode === 'signin' ? 'Come on in' : 'Join the community'}
        </button>
      </form>

      <button
        onClick={() => {
          haptic('select')
          setMode(mode === 'signin' ? 'signup' : 'signin')
          setError(null)
        }}
        className="press block mx-auto mt-6 text-sm transition-colors"
        style={{ color: 'var(--char-400)' }}
      >
        {mode === 'signin' ? 'New here? Create an account' : 'Already a member? Sign in'}
      </button>
    </div>
  )
}

export default function LoginPage() {
  return (
    <div
      className="min-h-screen flex items-center justify-center px-6 py-16 relative overflow-hidden"
      style={{ background: 'var(--sand-200)' }}
    >
      {/* warm texture rings */}
      <div
        aria-hidden
        className="pointer-events-none absolute inset-0"
        style={{
          background: [
            'radial-gradient(ellipse 80% 60% at 50% 100%, color-mix(in srgb, var(--pine-700) 8%, transparent) 0%, transparent 70%)',
            'radial-gradient(ellipse 50% 40% at 20% 10%, color-mix(in srgb, var(--honey-400) 12%, transparent) 0%, transparent 60%)',
          ].join(', '),
        }}
      />
      {/* subtle dot grid */}
      <div
        aria-hidden
        className="pointer-events-none absolute inset-0 opacity-[0.18]"
        style={{
          backgroundImage: 'radial-gradient(circle, var(--char-600) 1px, transparent 1px)',
          backgroundSize: '28px 28px',
        }}
      />

      <Suspense>
        <LoginForm />
      </Suspense>
    </div>
  )
}
