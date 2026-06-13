'use client'

import { useEffect } from 'react'
import Link from 'next/link'

export default function Error({
  error,
  reset,
}: {
  error: Error & { digest?: string }
  reset: () => void
}) {
  useEffect(() => {
    console.error('Route error boundary:', error)
  }, [error])

  return (
    <div className="min-h-screen flex items-center justify-center px-6 text-center">
      <div className="max-w-sm">
        <p className="font-display text-sky-500 tracking-[0.25em] uppercase text-base mb-6">Korina</p>
        <h1 className="font-display text-2xl text-ink mb-2">That didn’t load right</h1>
        <p className="text-sm text-ink-2 leading-relaxed mb-6">
          Something hit a snag on this screen. Try again — if it keeps happening, reload the app.
        </p>
        <div className="flex gap-2 justify-center">
          <button
            onClick={reset}
            className="bg-sky-700 hover:bg-sky-800 text-white font-semibold px-6 py-3 rounded-xl text-sm transition-colors"
          >
            Try again
          </button>
          <Link
            href="/dashboard"
            className="border border-black/[0.09] text-ink-2 hover:text-ink px-6 py-3 rounded-xl text-sm transition-colors hover:bg-paper-100"
          >
            Home
          </Link>
        </div>
      </div>
    </div>
  )
}
