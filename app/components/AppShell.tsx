'use client'

import Link from 'next/link'
import { usePathname, useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import {
  IconRings,
  IconBowl,
  IconBarcode,
  IconDumbbell,
  IconLogout,
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
      <aside className="hidden md:flex fixed inset-y-0 left-0 w-52 flex-col border-r border-white/[0.06] bg-bark-950 z-40">
        <Link
          href="/dashboard"
          className="font-display text-cream tracking-[0.25em] uppercase text-lg px-6 pt-7 pb-8"
        >
          Grove
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
                    ? 'bg-bark-800 text-cream'
                    : 'text-fog hover:text-cream hover:bg-bark-900'
                }`}
              >
                <tab.icon className={`w-[18px] h-[18px] ${active ? 'text-moss-400' : ''}`} />
                {tab.label}
              </Link>
            )
          })}
        </nav>
        <div className="px-3 pb-5">
          <button
            onClick={signOut}
            className="flex items-center gap-3 px-3 py-2.5 rounded-xl text-sm text-fog hover:text-cream hover:bg-bark-900 transition-colors w-full"
          >
            <IconLogout className="w-[18px] h-[18px]" />
            Sign out
          </button>
        </div>
      </aside>

      {/* mobile header */}
      <header className="md:hidden sticky top-0 z-40 flex items-center justify-between px-5 h-14 bg-bark-950/85 backdrop-blur-md border-b border-white/[0.06]">
        <Link href="/dashboard" className="font-display text-cream tracking-[0.25em] uppercase text-base">
          Grove
        </Link>
        <div className="flex items-center gap-4">
          <span className="font-mono text-[11px] text-fog uppercase tracking-wider">{dateLabel}</span>
          <button onClick={signOut} aria-label="Sign out" className="text-fog hover:text-cream transition-colors p-1 -m-1">
            <IconLogout className="w-[18px] h-[18px]" />
          </button>
        </div>
      </header>

      {/* page content; bottom padding clears the tab bar */}
      <main className="pb-28 md:pb-12">{children}</main>

      {/* mobile tab bar */}
      <nav
        className="md:hidden fixed bottom-0 inset-x-0 z-40 bg-bark-900/90 backdrop-blur-md border-t border-white/[0.06]"
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
                className="flex flex-col items-center justify-center gap-1"
              >
                {isScan ? (
                  <span
                    className={`flex items-center justify-center w-10 h-10 -mt-4 rounded-full border transition-colors ${
                      active
                        ? 'bg-moss-300 border-moss-300 text-bark-950'
                        : 'bg-moss-400 border-moss-400 text-bark-950'
                    }`}
                  >
                    <tab.icon className="w-5 h-5" />
                  </span>
                ) : (
                  <tab.icon
                    className={`w-[22px] h-[22px] transition-colors ${
                      active ? 'text-moss-300' : 'text-fog-dim'
                    }`}
                  />
                )}
                <span
                  className={`text-[10px] tracking-wide transition-colors ${
                    active ? 'text-cream' : 'text-fog-dim'
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
