'use client'

import dynamic from 'next/dynamic'
import { useState } from 'react'
import { haptic } from '@/lib/haptics'
import AppShell from '../components/AppShell'
import PhotoAnalyzer from '../components/PhotoAnalyzer'

const FoodScanner = dynamic(() => import('../components/FoodScanner'), { ssr: false })

type Mode = 'barcode' | 'photo'

export default function ScanPage() {
  const [mode, setMode] = useState<Mode>('barcode')

  return (
    <AppShell>
      <div className="max-w-md mx-auto px-5 pt-6 md:pt-10 pb-8">
        <header className="rise mb-5">
          <h1 className="font-display text-3xl text-ink">Scan</h1>
          <p className="text-sm text-ink-2 mt-2 leading-relaxed">
            {mode === 'barcode'
              ? 'Point at any barcode. Nutrition and clean score, instantly.'
              : 'Photograph your plate. AI breaks it down, food by food.'}
          </p>
        </header>

        <div className="rise grid grid-cols-2 gap-1 p-1 bg-paper-100 rounded-xl mb-5" style={{ animationDelay: '40ms' }}>
          {(
            [
              ['barcode', 'Barcode'],
              ['photo', 'Photo'],
            ] as [Mode, string][]
          ).map(([m, label]) => (
            <button
              key={m}
              onClick={() => { if (mode !== m) haptic('select'); setMode(m) }}
              className={`press py-2.5 rounded-lg text-sm transition-colors ${
                mode === m
                  ? 'bg-paper text-ink font-semibold shadow-sm'
                  : 'text-ink-2 hover:text-ink'
              }`}
            >
              {label}
            </button>
          ))}
        </div>

        {mode === 'barcode' ? <FoodScanner /> : <PhotoAnalyzer />}
      </div>
    </AppShell>
  )
}
