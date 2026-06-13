import Link from 'next/link'

export default function NotFound() {
  return (
    <div className="min-h-screen flex items-center justify-center px-6 text-center">
      <div className="max-w-sm">
        <p className="font-display text-sky-500 tracking-[0.25em] uppercase text-base mb-6">Korina</p>
        <p className="font-mono text-4xl text-ink tabular-nums mb-3">404</p>
        <h1 className="font-display text-2xl text-ink mb-2">Nothing here</h1>
        <p className="text-sm text-ink-2 leading-relaxed mb-6">
          That page doesn’t exist. Head back to your dashboard.
        </p>
        <Link
          href="/dashboard"
          className="inline-block bg-moss-700 hover:bg-moss-800 text-white font-semibold px-6 py-3 rounded-xl text-sm transition-colors"
        >
          Go to dashboard
        </Link>
      </div>
    </div>
  )
}
