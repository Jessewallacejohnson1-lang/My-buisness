'use client'

import Link from 'next/link'
import { useEffect, useRef, useState } from 'react'
import { lookupBarcode, scaleFood, toLogEntry, type FoodResult } from '@/lib/food-search'
import { addFoodLog, localDate } from '@/lib/db'
import ScoreRing, { scoreTone } from './ScoreRing'
import { IconAlert, IconBarcode, IconCheck, IconLeaf } from './Icons'

export const MEALS = ['Breakfast', 'Lunch', 'Dinner', 'Snacks'] as const
export type Meal = (typeof MEALS)[number]

export function mealForNow(): Meal {
  const h = new Date().getHours()
  if (h < 11) return 'Breakfast'
  if (h < 15) return 'Lunch'
  if (h >= 17 && h < 21) return 'Dinner'
  return 'Snacks'
}

export function MealPicker({ meal, onChange }: { meal: Meal; onChange: (m: Meal) => void }) {
  return (
    <div>
      <p className="text-[11px] uppercase tracking-[0.18em] text-ink-2 mb-2.5 px-0.5">Log as</p>
      <div className="grid grid-cols-4 gap-1.5">
        {MEALS.map((m) => (
          <button
            key={m}
            onClick={() => onChange(m)}
            className={`py-2.5 rounded-xl text-xs transition-colors border ${
              meal === m
                ? 'bg-moss-700 border-moss-700 text-white font-semibold'
                : 'bg-paper-50 border-black/[0.08] text-ink-2 hover:text-ink'
            }`}
          >
            {m}
          </button>
        ))}
      </div>
    </div>
  )
}

export default function FoodScanner() {
  const videoRef = useRef<HTMLVideoElement>(null)
  const [scanning, setScanning] = useState(false)
  const [result, setResult] = useState<FoodResult | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)
  const [meal, setMeal] = useState<Meal>(mealForNow())
  const [grams, setGrams] = useState(100)
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

      // Prefer the back camera on phones; falls back automatically on desktop.
      const controls = await reader.decodeFromConstraints(
        { video: { facingMode: 'environment' } },
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
        setError('That barcode isn’t in the database. Try another item or use Photo mode.')
        return
      }
      setResult(food)
      setMeal(mealForNow())
      setGrams(food.serving_grams ?? 100)
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
      await addFoodLog(toLogEntry(scaleFood(result, grams), meal, localDate()))
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
  const scaled = result ? scaleFood(result, grams) : null
  const presets = result?.serving_grams
    ? [{ label: `1 serving · ${result.serving_grams}g`, g: result.serving_grams }, { label: '50g', g: 50 }, { label: '100g', g: 100 }, { label: '200g', g: 200 }]
    : [{ label: '50g', g: 50 }, { label: '100g', g: 100 }, { label: '150g', g: 150 }, { label: '200g', g: 200 }]

  return (
    <div>
      {/* viewfinder */}
      {!result && (
        <div className="rise">
          <div className="relative rounded-3xl overflow-hidden bg-paper-100 border border-black/[0.08] aspect-square flex items-center justify-center">
            <video
              ref={videoRef}
              className={`w-full h-full object-cover ${scanning ? 'block' : 'hidden'}`}
              muted
              playsInline
            />
            {!scanning && !loading && (
              <div className="text-center px-10">
                <IconBarcode className="w-10 h-10 text-ink-3 mx-auto mb-4" />
                <p className="text-ink-3 text-sm">Camera preview appears here</p>
              </div>
            )}
            {scanning && (
              <div className="absolute inset-0 pointer-events-none">
                <div className="absolute inset-10">
                  <span className="absolute top-0 left-0 w-9 h-9 border-t-2 border-l-2 border-moss-700 rounded-tl-2xl" />
                  <span className="absolute top-0 right-0 w-9 h-9 border-t-2 border-r-2 border-moss-700 rounded-tr-2xl" />
                  <span className="absolute bottom-0 left-0 w-9 h-9 border-b-2 border-l-2 border-moss-700 rounded-bl-2xl" />
                  <span className="absolute bottom-0 right-0 w-9 h-9 border-b-2 border-r-2 border-moss-700 rounded-br-2xl" />
                  <span
                    className="absolute left-3 right-3 h-px bg-moss-700/80"
                    style={{
                      animation: 'beam 2.4s ease-in-out infinite',
                      boxShadow: '0 0 12px rgba(88,119,71,0.5)',
                    }}
                  />
                </div>
              </div>
            )}
            {loading && (
              <div className="absolute inset-0 bg-paper/70 backdrop-blur-sm flex flex-col items-center justify-center gap-3">
                <div className="w-8 h-8 border-2 border-moss-700 border-t-transparent rounded-full animate-spin" />
                <p className="text-ink-2 text-sm">Reading the label…</p>
              </div>
            )}
          </div>

          <div className="mt-4">
            {!scanning ? (
              <button
                onClick={startScanner}
                className="w-full bg-sky-700 hover:bg-sky-800 text-white font-semibold py-3.5 rounded-xl text-sm transition-colors"
              >
                Start scanning
              </button>
            ) : (
              <button
                onClick={stopScanner}
                className="w-full border border-black/[0.09] text-ink-2 hover:text-ink py-3.5 rounded-xl text-sm transition-colors hover:bg-paper-100"
              >
                Cancel
              </button>
            )}
          </div>

          {scanning && (
            <p className="text-center text-xs text-ink-3 mt-3">
              Hold steady — it detects automatically
            </p>
          )}

          {error && (
            <div className="mt-4 flex items-start gap-2.5 text-sm text-clay-700 bg-clay-700/10 border border-clay-700/20 rounded-2xl px-4 py-3.5 leading-relaxed">
              <IconAlert className="w-4 h-4 shrink-0 mt-0.5" />
              <span>{error}</span>
            </div>
          )}
        </div>
      )}

      {/* result */}
      {result && !loading && scaled && (
        <div className="rise space-y-4">
          <div className="bg-paper-50 border border-black/[0.07] rounded-3xl overflow-hidden">
            {result.image && (
              // eslint-disable-next-line @next/next/no-img-element
              <img
                src={result.image}
                alt={result.food_name}
                className="w-full h-44 object-contain bg-paper-100 p-4"
              />
            )}
            <div className="p-5">
              <div className="flex items-start justify-between gap-4 mb-5">
                <div className="min-w-0">
                  {result.brand && (
                    <p className="text-[11px] uppercase tracking-[0.18em] text-ink-2 mb-1 truncate">
                      {result.brand}
                    </p>
                  )}
                  <h2 className="text-lg text-ink leading-snug">{result.food_name}</h2>
                  {tone && (
                    <p className={`text-[11px] uppercase tracking-[0.18em] mt-1.5 ${tone.text}`}>
                      {tone.word}
                    </p>
                  )}
                </div>
                <ScoreRing score={result.score} size={56} />
              </div>

              {/* portion */}
              <div className="mb-4">
                <div className="flex items-baseline justify-between mb-2">
                  <p className="text-[11px] uppercase tracking-[0.18em] text-ink-2">Portion</p>
                  <span className="font-mono text-xs text-ink tabular-nums">{grams}g</span>
                </div>
                <div className="flex gap-1.5 flex-wrap">
                  {presets.map((p) => (
                    <button
                      key={p.label}
                      onClick={() => setGrams(p.g)}
                      className={`px-3 py-1.5 rounded-lg text-xs border transition-colors ${
                        grams === p.g
                          ? 'bg-ink border-ink text-white'
                          : 'bg-paper border-black/[0.08] text-ink-2 hover:text-ink'
                      }`}
                    >
                      {p.label}
                    </button>
                  ))}
                  <input
                    type="number"
                    min={1}
                    value={grams}
                    onChange={(e) => setGrams(Math.max(1, parseInt(e.target.value) || 1))}
                    aria-label="Portion in grams"
                    className="w-20 px-2 py-1.5 rounded-lg text-xs bg-paper border border-black/[0.08] text-ink font-mono tabular-nums focus:border-moss-700/50 focus:outline-none"
                  />
                </div>
              </div>

              <div className="grid grid-cols-4 gap-2 mb-4">
                {[
                  { label: 'kcal', value: scaled.calories },
                  { label: 'protein', value: `${scaled.protein}g` },
                  { label: 'carbs', value: `${scaled.carbs}g` },
                  { label: 'fat', value: `${scaled.fat}g` },
                ].map((m) => (
                  <div
                    key={m.label}
                    className="bg-paper-100 border border-black/[0.06] rounded-xl py-3 text-center"
                  >
                    <p className="font-mono text-sm text-ink tabular-nums">{m.value}</p>
                    <p className="text-[10px] text-ink-3 mt-0.5">{m.label}</p>
                  </div>
                ))}
              </div>

              {result.badges.length > 0 && (
                <div className="flex flex-wrap gap-1.5 mb-3">
                  {result.badges.map((b) => (
                    <span
                      key={b.label}
                      className="inline-flex items-center gap-1.5 text-[11px] text-moss-700 bg-moss-700/10 border border-moss-700/20 px-2.5 py-1 rounded-full"
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
                  className="flex items-start gap-2.5 text-xs text-clay-700 bg-clay-700/10 border border-clay-700/20 rounded-xl px-3 py-2.5 mb-1.5 leading-relaxed"
                >
                  <IconAlert className="w-3.5 h-3.5 shrink-0 mt-px" />
                  <span>{f}</span>
                </div>
              ))}
            </div>
          </div>

          {saved ? (
            <div className="bg-moss-700/10 border border-moss-700/25 rounded-2xl p-5 text-center">
              <div className="mx-auto mb-3 w-10 h-10 rounded-full bg-moss-700 text-white flex items-center justify-center">
                <IconCheck className="w-5 h-5" strokeWidth={2.5} />
              </div>
              <p className="text-sm text-ink mb-4">
                Logged {grams}g to {meal.toLowerCase()}.
              </p>
              <div className="flex gap-2">
                <button
                  onClick={() => {
                    setResult(null)
                    setSaved(false)
                    setError(null)
                  }}
                  className="flex-1 py-3 rounded-xl bg-sky-700 hover:bg-sky-800 text-white text-sm font-semibold transition-colors"
                >
                  Scan another
                </button>
                <Link
                  href="/meal-log"
                  className="flex-1 py-3 rounded-xl border border-black/[0.09] text-ink text-sm text-center hover:bg-paper-100 transition-colors"
                >
                  View meals
                </Link>
              </div>
            </div>
          ) : (
            <>
              <MealPicker meal={meal} onChange={setMeal} />

              {error && (
                <div className="flex items-start gap-2.5 text-sm text-clay-700 bg-clay-700/10 border border-clay-700/20 rounded-2xl px-4 py-3.5 leading-relaxed">
                  <IconAlert className="w-4 h-4 shrink-0 mt-0.5" />
                  <span>{error}</span>
                </div>
              )}

              <button
                onClick={handleSave}
                disabled={saving}
                className="w-full bg-sky-700 hover:bg-sky-800 text-white font-semibold py-3.5 rounded-xl text-sm transition-colors disabled:opacity-60"
              >
                {saving ? 'Saving…' : `Add ${grams}g to ${meal.toLowerCase()}`}
              </button>
              <button
                onClick={() => {
                  setResult(null)
                  setError(null)
                }}
                className="w-full border border-black/[0.09] text-ink-2 hover:text-ink py-3.5 rounded-xl text-sm transition-colors hover:bg-paper-100"
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
