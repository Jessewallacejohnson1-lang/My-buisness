'use client'

import Link from 'next/link'
import { usePathname, useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { haptic } from '@/lib/haptics'
import {
  IconRings,
  IconBowl,
  IconBarcode,
  IconDumbbell,
  IconLogout,
  IconSliders,
} from './Icons'

const TABS = [
  { href: '/dashboard', label: 'Today', icon: IconRings },
  { href: '/meal-log', label: 'Meals', icon: IconBowl },
  { href: '/scan', label: 'Scan', icon: IconBarcode },
  { href: '/workouts', label: 'Train', icon: IconDumbbell },
]

export default function AppShell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname()
  const router = useRouter()

  const signOut = async () => {
    await createClient().auth.signOut()
    router.push('/')
    router.refresh()
  }

  const dateLabel = new Date().toLocaleDateString('en-US', {
    weekday: 'short',
    month: 'short',
    day: 'numeric',
  })

  return (
    <div className="min-h-screen md:pl-52">
      {/* desktop rail */}
      <aside className="hidden md:flex fixed inset-y-0 left-0 w-52 flex-col border-r border-black/[0.07] bg-paper z-40">
        <Link
          href="/dashboard"
          className="font-display text-sky-600 tracking-[0.25em] uppercase text-lg px-6 pt-7 pb-8"
        >
          Korina
        </Link>
        <nav className="flex-1 px-3 space-y-1">
          {TABS.map((tab) => {
            const active = pathname === tab.href
            return (
              <Link
                key={tab.href}
                href={tab.href}
                className={`flex items-center gap-3 px-3 py-2.5 rounded-xl text-sm transition-colors ${
                  active
                    ? 'bg-paper-100 text-ink'
                    : 'text-ink-2 hover:text-ink hover:bg-paper-50'
                }`}
              >
                <tab.icon className={`w-[18px] h-[18px] ${active ? 'text-moss-700' : ''}`} />
                {tab.label}
              </Link>
            )
          })}
        </nav>
        <div className="px-3 pb-5 space-y-1">
          <Link
            href="/onboarding"
            className={`flex items-center gap-3 px-3 py-2.5 rounded-xl text-sm transition-colors ${
              pathname === '/onboarding'
                ? 'bg-paper-100 text-ink'
                : 'text-ink-2 hover:text-ink hover:bg-paper-50'
            }`}
          >
            <IconSliders className="w-[18px] h-[18px]" />
            Goals
          </Link>
          <button
            onClick={signOut}
            className="flex items-center gap-3 px-3 py-2.5 rounded-xl text-sm text-ink-2 hover:text-ink hover:bg-paper-50 transition-colors w-full"
          >
            <IconLogout className="w-[18px] h-[18px]" />
            Sign out
          </button>
        </div>
      </aside>

      {/* mobile header */}
      <header className="md:hidden sticky top-0 z-40 flex items-center justify-between px-5 h-14 bg-paper/85 backdrop-blur-md border-b border-black/[0.07]">
        <Link href="/dashboard" className="font-display text-sky-600 tracking-[0.25em] uppercase text-base">
          Korina
        </Link>
        <div className="flex items-center gap-4">
          <span className="font-mono text-[11px] text-ink-2 uppercase tracking-wider">{dateLabel}</span>
          <Link href="/onboarding" aria-label="Edit goals" className="text-ink-2 hover:text-ink transition-colors p-1 -m-1">
            <IconSliders className="w-[18px] h-[18px]" />
          </Link>
          <button onClick={signOut} aria-label="Sign out" className="text-ink-2 hover:text-ink transition-colors p-1 -m-1">
            <IconLogout className="w-[18px] h-[18px]" />
          </button>
        </div>
      </header>

      {/* page content; bottom padding clears the tab bar */}
      <main className="pb-28 md:pb-12">{children}</main>

      {/* mobile tab bar */}
      <nav
        className="md:hidden fixed bottom-0 inset-x-0 z-40 bg-paper-50/90 backdrop-blur-md border-t border-black/[0.07]"
        style={{ paddingBottom: 'env(safe-area-inset-bottom)' }}
      >
        <div className="grid grid-cols-4 h-16">
          {TABS.map((tab) => {
            const active = pathname === tab.href
            const isScan = tab.href === '/scan'
            return (
              <Link
                key={tab.href}
                href={tab.href}
                onClick={() => { if (!active) haptic('select') }}
                className="press flex flex-col items-center justify-center gap-1"
              >
                {isScan ? (
                  <span
                    className={`flex items-center justify-center w-10 h-10 -mt-4 rounded-full border transition-colors ${
                      active
                        ? 'bg-moss-700 border-moss-700 text-white'
                        : 'bg-paper border-black/[0.15] text-ink-2'
                    }`}
                  >
                    <tab.icon className="w-5 h-5" />
                  </span>
                ) : (
                  <tab.icon
                    className={`w-[22px] h-[22px] transition-colors ${
                      active ? 'text-moss-700' : 'text-ink-3'
                    }`}
                  />
                )}
                <span
                  className={`text-[10px] tracking-wide transition-colors ${
                    active ? 'text-ink' : 'text-ink-3'
                  } ${isScan ? '-mt-0.5' : ''}`}
                >
                  {tab.label}
                </span>
              </Link>
            )
          })}
        </div>
      </nav>
    </div>
  )
}
