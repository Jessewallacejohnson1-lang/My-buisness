'use client'

import { useEffect, useRef, useState } from 'react'

type RingSpec = {
  /** 0..1 */
  pct: number
  color: string
}

/**
 * Concentric growth rings — Grove's signature dial.
 * Rings sweep in from zero on mount, outermost first.
 */
export function GrowthRings({
  rings,
  size = 220,
  children,
}: {
  rings: RingSpec[]
  size?: number
  children?: React.ReactNode
}) {
  const [mounted, setMounted] = useState(false)
  useEffect(() => {
    const id = requestAnimationFrame(() => setMounted(true))
    return () => cancelAnimationFrame(id)
  }, [])

  const stroke = 10
  const gap = 7
  const outer = 100 - stroke / 2

  return (
    <div className="relative shrink-0" style={{ width: size, height: size }}>
      <svg viewBox="0 0 200 200" width={size} height={size} className="-rotate-90">
        {rings.map((ring, i) => {
          const r = outer - i * (stroke + gap)
          const circ = 2 * Math.PI * r
          const target = circ * (1 - Math.max(0, Math.min(1, ring.pct)))
          return (
            <g key={i}>
              <circle
                cx="100"
                cy="100"
                r={r}
                fill="none"
                stroke="rgba(255,255,255,0.06)"
                strokeWidth={stroke}
              />
              <circle
                cx="100"
                cy="100"
                r={r}
                fill="none"
                stroke={ring.color}
                strokeWidth={stroke}
                strokeLinecap="round"
                strokeDasharray={circ}
                strokeDashoffset={mounted ? target : circ}
                className="ring-sweep"
                style={{ transitionDelay: `${i * 120}ms` }}
              />
            </g>
          )
        })}
      </svg>
      {children && (
        <div className="absolute inset-0 flex flex-col items-center justify-center">
          {children}
        </div>
      )}
    </div>
  )
}

/** Animated count-up for hero numbers. Respects prefers-reduced-motion. */
export function useCountUp(target: number, duration = 700): number {
  const [value, setValue] = useState(0)
  const prev = useRef(0)

  useEffect(() => {
    const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches
    const from = prev.current
    prev.current = target
    const start = performance.now()
    let raf: number
    const tick = (now: number) => {
      if (reduced) {
        setValue(target)
        return
      }
      const t = Math.min(1, (now - start) / duration)
      const eased = 1 - Math.pow(1 - t, 3)
      setValue(Math.round(from + (target - from) * eased))
      if (t < 1) raf = requestAnimationFrame(tick)
    }
    raf = requestAnimationFrame(tick)
    return () => cancelAnimationFrame(raf)
  }, [target, duration])

  return value
}
