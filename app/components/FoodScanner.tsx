'use client'

import Link from 'next/link'
import { useEffect, useRef, useState } from 'react'
import { lookupBarcode, toLogEntry, type FoodResult } from '@/lib/food-search'
import { addFoodLog, localDate } from '@/lib/db'
import ScoreRing, { scoreTone } from './ScoreRing'
import { IconAlert, IconBarcode, IconCheck, IconLeaf } from './Icons'

const MEALS = ['Breakfast', 'Lunch', 'Dinner', 'Snacks'] as const
type Meal = (typeof MEALS)[number]

function mealForNow(): Meal {
  const h = new Date().getHours()
  if (h < 11) return 'Breakfast'
  if (h < 15) return 'Lunch'
  if (h >= 17 && h < 21) return 'Dinner'
  return 'Snacks'
}

export default function FoodScanner() {
  const videoRef = useRef<HTMLVideoElement>(null)
  const [scanning, setScanning] = useState(false)
  const [result, setResult] = useState<FoodResult | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)
  const [meal, setMeal] = useState<Meal>(mealForNow())
  const [saving, setSaving] = useState(false)
  const [saved, setSaved] = useState(false)
  const stopRef = useRef<(() => void) | null>(null)

  const startScanner = async () => {
    setScanning(true)
    setResult(null)
    setError(null)
    setSaved(false)

    try {
      const { BrowserMultiFormatReader } = await import('@zxing/browser')
      const reader = new BrowserMultiFormatReader()

      const controls = await reader.decodeFromVideoDevice(
        undefined,
        videoRef.current!,
        async (scanResult, _err, ctrl) => {
          if (scanResult) {
            ctrl.stop()
            stopRef.current = null
            setScanning(false)
            await lookupFood(scanResult.getText())
          }
        }
      )

      stopRef.current = () => controls.stop()
    } catch {
      setScanning(false)
      setError('Camera unavailable. Allow camera access and try again.')
    }
  }

  const stopScanner = () => {
    if (stopRef.current) {
      stopRef.current()
      stopRef.current = null
    }
    setScanning(false)
  }

  const lookupFood = async (barcode: string) => {
    setLoading(true)
    try {
      const food = await lookupBarcode(barcode)
      if (!food) {
        setError('That barcode isn’t in the database. Try another item or search it by name.')
        return
      }
      setResult(food)
      setMeal(mealForNow())
    } catch {
      setError('Couldn’t fetch the food data. Check your connection and try again.')
    } finally {
      setLoading(false)
    }
  }

  const handleSave = async () => {
    if (!result) return
    setSaving(true)
    try {
      await addFoodLog(toLogEntry(result, meal, localDate()))
      setSaved(true)
    } catch {
      setError('Couldn’t save the log. Try again.')
    } finally {
      setSaving(false)
    }
  }

  useEffect(() => {
    return () => {
      if (stopRef.current) stopRef.current()
    }
  }, [])

  const tone = result ? scoreTone(result.score) : null

  return (
    <div className="max-w-md mx-auto px-5 pt-6 md:pt-10 pb-8">
      <header className="rise mb-6">
        <h1 className="font-display text-3xl text-cream">Scan</h1>
        <p className="text-sm text-fog mt-2 leading-relaxed">
          Point at any barcode. Nutrition and clean score, instantly.
        </p>
      </header>

      {/* viewfinder */}
      {!result && (
        <div className="rise" style={{ animationDelay: '60ms' }}>
          <div className="relative rounded-3xl overflow-hidden bg-bark-900 border border-white/[0.08] aspect-square flex items-center justify-center">
            <video
              ref={videoRef}
              className={`w-full h-full object-cover ${scanning ? 'block' : 'hidden'}`}
              muted
              playsInline
            />
            {!scanning && !loading && (
              <div className="text-center px-10">
                <IconBarcode className="w-10 h-10 text-fog-dim mx-auto mb-4" />
                <p className="text-fog-dim text-sm">Camera preview appears here</p>
              </div>
            )}
            {scanning && (
              <div className="absolute inset-0 pointer-events-none">
                <div className="absolute inset-10">
                  <span className="absolute top-0 left-0 w-9 h-9 border-t-2 border-l-2 border-moss-300 rounded-tl-2xl" />
                  <span className="absolute top-0 right-0 w-9 h-9 border-t-2 border-r-2 border-moss-300 rounded-tr-2xl" />
                  <span className="absolute bottom-0 left-0 w-9 h-9 border-b-2 border-l-2 border-moss-300 rounded-bl-2xl" />
                  <span className="absolute bottom-0 right-0 w-9 h-9 border-b-2 border-r-2 border-moss-300 rounded-br-2xl" />
                  <span
                    className="absolute left-3 right-3 h-px bg-moss-300/80"
                    style={{
                      animation: 'beam 2.4s ease-in-out infinite',
                      boxShadow: '0 0 12px rgba(191,211,175,0.5)',
                    }}
                  />
                </div>
              </div>
            )}
            {loading && (
              <div className="absolute inset-0 bg-bark-950/70 backdrop-blur-sm flex flex-col items-center justify-center gap-3">
                <div className="w-8 h-8 border-2 border-moss-400 border-t-transparent rounded-full animate-spin" />
                <p className="text-fog text-sm">Reading the label…</p>
              </div>
            )}
          </div>

          <div className="mt-4">
            {!scanning ? (
              <button
                onClick={startScanner}
                className="w-full bg-moss-400 hover:bg-moss-300 text-bark-950 font-semibold py-3.5 rounded-xl text-sm transition-colors"
              >
                Start scanning
              </button>
            ) : (
              <button
                onClick={stopScanner}
                className="w-full border border-white/[0.08] text-fog hover:text-cream py-3.5 rounded-xl text-sm transition-colors hover:bg-bark-800"
              >
                Cancel
              </button>
            )}
          </div>

          {scanning && (
            <p className="text-center text-xs text-fog-dim mt-3">
              Hold steady — it detects automatically
            </p>
          )}

          {error && (
            <div className="mt-4 flex items-start gap-2.5 text-sm text-clay-300 bg-clay-500/10 border border-clay-500/20 rounded-2xl px-4 py-3.5 leading-relaxed">
              <IconAlert className="w-4 h-4 shrink-0 mt-0.5" />
              <span>{error}</span>
            </div>
          )}
        </div>
      )}

      {/* result */}
      {result && !loading && (
        <div className="rise space-y-4">
          <div className="bg-bark-900 border border-white/[0.06] rounded-3xl overflow-hidden">
            {result.image && (
              // eslint-disable-next-line @next/next/no-img-element
              <img
                src={result.image}
                alt={result.food_name}
                className="w-full h-44 object-contain bg-bark-800 p-4"
              />
            )}
            <div className="p-5">
              <div className="flex items-start justify-between gap-4 mb-5">
                <div className="min-w-0">
                  {result.brand && (
                    <p className="text-[11px] uppercase tracking-[0.18em] text-fog mb-1 truncate">
                      {result.brand}
                    </p>
                  )}
                  <h2 className="text-lg text-cream leading-snug">{result.food_name}</h2>
                  {tone && (
                    <p className={`text-[11px] uppercase tracking-[0.18em] mt-1.5 ${tone.text}`}>
                      {tone.word}
                    </p>
                  )}
                </div>
                <ScoreRing score={result.score} size={56} />
              </div>

              <div className="grid grid-cols-4 gap-2 mb-4">
                {[
                  { label: 'kcal', value: result.calories },
                  { label: 'protein', value: `${result.protein}g` },
                  { label: 'carbs', value: `${result.carbs}g` },
                  { label: 'fat', value: `${result.fat}g` },
                ].map((m) => (
                  <div
                    key={m.label}
                    className="bg-bark-800 border border-white/[0.05] rounded-xl py-3 text-center"
                  >
                    <p className="font-mono text-sm text-cream tabular-nums">{m.value}</p>
                    <p className="text-[10px] text-fog-dim mt-0.5">{m.label}</p>
                  </div>
                ))}
              </div>

              {result.badges.length > 0 && (
                <div className="flex flex-wrap gap-1.5 mb-3">
                  {result.badges.map((b) => (
                    <span
                      key={b.label}
                      className="inline-flex items-center gap-1.5 text-[11px] text-moss-300 bg-moss-500/10 border border-moss-500/20 px-2.5 py-1 rounded-full"
                    >
                      <IconLeaf className="w-3 h-3" />
                      {b.label}
                    </span>
                  ))}
                </div>
              )}
              {result.flags.map((f) => (
                <div
                  key={f}
                  className="flex items-start gap-2.5 text-xs text-clay-300 bg-clay-500/10 border border-clay-500/20 rounded-xl px-3 py-2.5 mb-1.5 leading-relaxed"
                >
                  <IconAlert className="w-3.5 h-3.5 shrink-0 mt-px" />
                  <span>{f}</span>
                </div>
              ))}
            </div>
          </div>

          {saved ? (
            <div className="bg-moss-500/10 border border-moss-500/25 rounded-2xl p-5 text-center">
              <div className="mx-auto mb-3 w-10 h-10 rounded-full bg-moss-400 text-bark-950 flex items-center justify-center">
                <IconCheck className="w-5 h-5" strokeWidth={2.5} />
              </div>
              <p className="text-sm text-cream mb-4">
                Logged to {meal.toLowerCase()}.
              </p>
              <div className="flex gap-2">
                <button
                  onClick={() => {
                    setResult(null)
                    setSaved(false)
                    setError(null)
                  }}
                  className="flex-1 py-3 rounded-xl bg-moss-400 hover:bg-moss-300 text-bark-950 text-sm font-semibold transition-colors"
                >
                  Scan another
                </button>
                <Link
                  href="/meal-log"
                  className="flex-1 py-3 rounded-xl border border-white/[0.08] text-cream text-sm text-center hover:bg-bark-800 transition-colors"
                >
                  View meals
                </Link>
              </div>
            </div>
          ) : (
            <>
              <div>
                <p className="text-[11px] uppercase tracking-[0.18em] text-fog mb-2.5 px-0.5">
                  Log as
                </p>
                <div className="grid grid-cols-4 gap-1.5">
                  {MEALS.map((m) => (
                    <button
                      key={m}
                      onClick={() => setMeal(m)}
                      className={`py-2.5 rounded-xl text-xs transition-colors border ${
                        meal === m
                          ? 'bg-moss-400 border-moss-400 text-bark-950 font-semibold'
                          : 'bg-bark-900 border-white/[0.07] text-fog hover:text-cream'
                      }`}
                    >
                      {m}
                    </button>
                  ))}
                </div>
              </div>

              {error && (
                <div className="flex items-start gap-2.5 text-sm text-clay-300 bg-clay-500/10 border border-clay-500/20 rounded-2xl px-4 py-3.5 leading-relaxed">
                  <IconAlert className="w-4 h-4 shrink-0 mt-0.5" />
                  <span>{error}</span>
                </div>
              )}

              <button
                onClick={handleSave}
                disabled={saving}
                className="w-full bg-moss-400 hover:bg-moss-300 text-bark-950 font-semibold py-3.5 rounded-xl text-sm transition-colors disabled:opacity-60"
              >
                {saving ? 'Saving…' : `Add to ${meal.toLowerCase()}`}
              </button>
              <button
                onClick={() => {
                  setResult(null)
                  setError(null)
                }}
                className="w-full border border-white/[0.08] text-fog hover:text-cream py-3.5 rounded-xl text-sm transition-colors hover:bg-bark-800"
              >
                Scan another
              </button>
            </>
          )}
        </div>
      )}
    </div>
  )
}
