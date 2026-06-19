'use client'

import type { ScoreReason } from '@/lib/food-search'
import { IconChevronDown } from './Icons'

/**
 * "Why this score" — the defensibility layer. Lists every signal that moved the
 * score off its 70 baseline, with the exact points. If a user thinks broccoli's
 * 92 or a soda's 28 is wrong, this is the receipt.
 */
export default function ScoreWhy({
  score,
  reasons,
  open,
  onToggle,
}: {
  score: number
  reasons: ScoreReason[]
  open: boolean
  onToggle: () => void
}) {
  if (!reasons || reasons.length === 0) return null

  // Biggest movers first; zero-delta notes (e.g. "limited data") sink to the end.
  const ordered = [...reasons].sort((a, b) => Math.abs(b.delta) - Math.abs(a.delta))

  return (
    <div className="mt-5 pt-4 border-t border-black/[0.07]">
      <button
        onClick={onToggle}
        aria-expanded={open}
        className="press w-full flex items-center justify-between text-left"
      >
        <span className="text-[11px] uppercase tracking-[0.18em] text-ink-2">Why this score</span>
        <span className="flex items-center gap-1.5">
          <span className="font-mono text-sm text-ink tabular-nums">{score}</span>
          <IconChevronDown className={`w-4 h-4 text-ink-3 transition-transform ${open ? 'rotate-180' : ''}`} />
        </span>
      </button>

      {open && (
        <div className="mt-3 space-y-1.5">
          <div className="flex items-center justify-between text-xs">
            <span className="text-ink-3">Baseline</span>
            <span className="font-mono text-ink-3 tabular-nums">70</span>
          </div>
          {ordered.map((r, i) => (
            <div key={`${r.label}-${i}`} className="flex items-center justify-between text-xs gap-3">
              <span className="text-ink-2">{r.label}</span>
              <span
                className={`font-mono tabular-nums shrink-0 ${
                  r.delta > 0 ? 'text-moss-700' : r.delta < 0 ? 'text-clay-700' : 'text-ink-3'
                }`}
              >
                {r.delta > 0 ? '+' : ''}{r.delta === 0 ? '·' : r.delta}
              </span>
            </div>
          ))}
          <div className="flex items-center justify-between text-xs pt-1.5 mt-1.5 border-t border-black/[0.06]">
            <span className="text-ink font-medium">Clean score</span>
            <span className="font-mono text-ink tabular-nums font-medium">{score}</span>
          </div>
        </div>
      )}
    </div>
  )
}
