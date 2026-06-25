'use client'

import { useEffect, useRef } from 'react'

/**
 * Scroll reveal. Content is visible by default (no-JS safe);
 * below-the-fold elements are hidden on mount and rise in when scrolled to.
 */
export default function Reveal({
  children,
  className = '',
}: {
  children: React.ReactNode
  className?: string
}) {
  const ref = useRef<HTMLDivElement>(null)

  useEffect(() => {
    const el = ref.current
    if (!el) return
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return
    // Already on screen — show immediately, no animation, no flash.
    if (el.getBoundingClientRect().top < window.innerHeight) return

    el.classList.add('reveal-pending')
    const io = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) {
          el.classList.add('reveal-in')
          io.disconnect()
        }
      },
      { threshold: 0.15, rootMargin: '0px 0px -40px 0px' }
    )
    io.observe(el)
    return () => io.disconnect()
  }, [])

  return (
    <div ref={ref} className={className}>
      {children}
    </div>
  )
}
