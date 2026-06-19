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
  IconTrend,
  IconLogout,
  IconSliders,
} from './Icons'

function HyggeFlame({ size = 18 }: { size?: number }) {
  return (
    <svg viewBox="0 0 24 24" width={size} height={size} fill="none" stroke="currentColor"
      strokeWidth={1.5} strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <path d="M12 21c-4 0-6.5-2.6-6.5-6 0-2.5 1.4-4.4 2.7-6C9.4 7.6 10.5 6 10.5 3.5c3 1.5 4 4.5 3.5 6.5 1-.5 1.8-1.3 2-2.5 1.6 1.7 2.5 3.9 2.5 6 0 3.4-2.5 7.5-6.5 7.5Z" />
    </svg>
  )
}

function IconCommunity({ size = 18, className = '' }: { size?: number; className?: string }) {
  return (
    <svg viewBox="0 0 24 24" width={size} height={size} className={className} fill="none" stroke="currentColor"
      strokeWidth={1.5} strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2" /><circle cx="9" cy="7" r="4" />
      <path d="M23 21v-2a4 4 0 0 0-3-3.87" /><path d="M16 3.13a4 4 0 0 1 0 7.75" />
    </svg>
  )
}

const TABS = [
  { href: '/dashboard', label: 'Today', icon: IconRings },
  { href: '/meal-log', label: 'Meals', icon: IconBowl },
  { href: '/scan', label: 'Scan', icon: IconBarcode },
  { href: '/workouts', label: 'Train', icon: IconDumbbell },
  { href: '/progress', label: 'Progress', icon: IconTrend },
]

export default function AppShell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname()
  const router = useRouter()

  const signOut = async () => {
    haptic('tap')
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
          className="font-display text-ink tracking-[0.28em] uppercase text-base font-medium px-6 pt-7 pb-8 flex items-center gap-2.5"
        >
          <HyggeFlame />
          HYGGE
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
            href="/community"
            className={`flex items-center gap-3 px-3 py-2.5 rounded-xl text-sm transition-colors ${
              pathname.startsWith('/community')
                ? 'bg-paper-100 text-ink'
                : 'text-ink-2 hover:text-ink hover:bg-paper-50'
            }`}
          >
            <IconCommunity size={18} className={pathname.startsWith('/community') ? 'text-sky-600' : ''} />
            Community
          </Link>
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
        <Link href="/dashboard" className="font-display text-ink tracking-[0.28em] uppercase text-sm font-medium flex items-center gap-2">
          <HyggeFlame size={16} />
          HYGGE
        </Link>
        <div className="flex items-center gap-4">
          <span className="font-mono text-[11px] text-ink-2 uppercase tracking-wider">{dateLabel}</span>
          <Link href="/community" aria-label="Community" className="text-ink-2 hover:text-ink transition-colors p-1 -m-1">
            <IconCommunity size={18} />
          </Link>
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
        <div className="grid grid-cols-5 h-16">
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
