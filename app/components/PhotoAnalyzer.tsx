'use client'

import Link from 'next/link'
import { useRef, useState } from 'react'
import { addFoodLog, localDate } from '@/lib/db'
import ScoreRing from './ScoreRing'
import { IconAlert, IconCheck, IconLeaf } from './Icons'
import { MealPicker, mealForNow, type Meal } from './FoodScanner'
import type { PhotoAnalysis } from '@/app/api/analyze/route'

type Stage = 'idle' | 'analyzing' | 'results' | 'saved'

/** Downscales to ≤1280px JPEG so uploads stay small and token cost stays low. */
async function toBase64Jpeg(file: File): Promise<string> {
  const bitmap = await createImageBitmap(file)
  const scale = Math.min(1, 1280 / Math.max(bitmap.width, bitmap.height))
  const canvas = document.createElement('canvas')
  canvas.width = Math.round(bitmap.width * scale)
  canvas.height = Math.round(bitmap.height * scale)
  canvas.getContext('2d')!.drawImage(bitmap, 0, 0, canvas.width, canvas.height)
  return canvas.toDataURL('image/jpeg', 0.8).split(',')[1]
}

export default function PhotoAnalyzer() {
  const inputRef = useRef<HTMLInputElement>(null)
  const [stage, setStage] = useState<Stage>('idle')
  const [preview, setPreview] = useState<string | null>(null)
  const [analysis, setAnalysis] = useState<PhotoAnalysis | null>(null)
  const [included, setIncluded] = useState<boolean[]>([])
  const [meal, setMeal] = useState<Meal>(mealForNow())
  const [error, setError] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)
  const [savedCount, setSavedCount] = useState(0)

  const analyze = async (file: File) => {
    setError(null)
    setStage('analyzing')
    setPreview(URL.createObjectURL(file))
    try {
      const image = await toBase64Jpeg(file)
      const res = await fetch('/api/analyze', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ image, media_type: 'image/jpeg' }),
      })
      const data = await res.json()
      if (!res.ok) throw new Error(data.error ?? 'Analysis failed.')
      if (!data.foods?.length) {
        setError(data.note || 'No food found in that photo. Try another angle.')
        setStage('idle')
        return
      }
      setAnalysis(data)
      setIncluded(data.foods.map(() => true))
      setMeal(mealForNow())
      setStage('results')
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Analysis failed. Try again.')
      setStage('idle')
    }
  }

  const handleSave = async () => {
    if (!analysis) return
    const foods = analysis.foods.filter((_, i) => included[i])
    if (foods.length === 0) return
    setSaving(true)
    setError(null)
    try {
      for (const f of foods) {
        await addFoodLog({
          food_name: f.name,
          brand: null,
          calories: Math.round(f.calories),
          protein: Math.round(f.protein * 10) / 10,
          carbs: Math.round(f.carbs * 10) / 10,
          fat: Math.round(f.fat * 10) / 10,
          fibre: Math.round(f.fibre * 10) / 10,
          score: Math.max(1, Math.min(100, Math.round(f.score))),
          badges: f.badges.map((label) => ({ label, icon: '', color: '' })),
          flags: f.flags,
          meal,
          date: localDate(),
        })
      }
      setSavedCount(foods.length)
      setStage('saved')
    } catch {
      setError('Couldn’t save the log. Try again.')
    } finally {
      setSaving(false)
    }
  }

  const reset = () => {
    setStage('idle')
    setAnalysis(null)
    setPreview(null)
    setError(null)
  }

  const totals = analysis
    ? analysis.foods.reduce(
        (t, f, i) => (included[i] ? { cal: t.cal + f.calories, n: t.n + 1 } : t),
        { cal: 0, n: 0 }
      )
    : { cal: 0, n: 0 }

  return (
    <div>
      <input
        ref={inputRef}
        type="file"
        accept="image/*"
        capture="environment"
        className="hidden"
        onChange={(e) => {
          const file = e.target.files?.[0]
          if (file) analyze(file)
          e.target.value = ''
        }}
      />

      {stage === 'idle' && (
        <div className="rise">
          <button
            onClick={() => inputRef.current?.click()}
            className="w-full rounded-3xl bg-paper-100 border border-dashed border-black/[0.12] aspect-square flex flex-col items-center justify-center gap-4 hover:border-moss-700/50 transition-colors"
          >
            <svg viewBox="0 0 24 24" className="w-10 h-10 text-ink-3" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
              <path d="M3 8a2 2 0 0 1 2-2h1.5l1.2-1.8A1 1 0 0 1 8.5 4h7a1 1 0 0 1 .8.4L17.5 6H19a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8Z" />
              <circle cx="12" cy="12.5" r="3.5" />
            </svg>
            <div className="text-center px-8">
              <p className="text-sm text-ink">Photograph your plate</p>
              <p className="text-xs text-ink-3 mt-1.5 leading-relaxed">
                AI identifies each food, estimates portions and macros, and scores it
              </p>
            </div>
          </button>

          {error && (
            <div className="mt-4 flex items-start gap-2.5 text-sm text-clay-700 bg-clay-700/10 border border-clay-700/20 rounded-2xl px-4 py-3.5 leading-relaxed">
              <IconAlert className="w-4 h-4 shrink-0 mt-0.5" />
              <span>{error}</span>
            </div>
          )}
        </div>
      )}

      {stage === 'analyzing' && (
        <div className="rise relative rounded-3xl overflow-hidden border border-black/[0.08] aspect-square">
          {preview && (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={preview} alt="Your meal" className="w-full h-full object-cover" />
          )}
          <div className="absolute inset-0 bg-paper/70 backdrop-blur-sm flex flex-col items-center justify-center gap-3">
            <div className="w-8 h-8 border-2 border-moss-700 border-t-transparent rounded-full animate-spin" />
            <p className="text-ink-2 text-sm">Reading your plate…</p>
          </div>
        </div>
      )}

      {stage === 'results' && analysis && (
        <div className="rise space-y-4">
          {preview && (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={preview}
              alt="Your meal"
              className="w-full h-40 object-cover rounded-3xl border border-black/[0.08]"
            />
          )}

          <p className="text-xs text-ink-3 leading-relaxed px-0.5">
            {analysis.note} Estimates from a photo — tap any item to exclude it.
          </p>

          <div className="space-y-2">
            {analysis.foods.map((f, i) => (
              <button
                key={i}
                onClick={() =>
                  setIncluded((arr) => arr.map((v, j) => (j === i ? !v : v)))
                }
                className={`w-full text-left bg-paper-50 border rounded-2xl px-4 py-3.5 flex items-start gap-3.5 transition-all ${
                  included[i] ? 'border-black/[0.07]' : 'border-black/[0.05] opacity-40'
                }`}
              >
                <ScoreRing score={Math.max(1, Math.min(100, Math.round(f.score)))} />
                <div className="flex-1 min-w-0">
                  <p className="text-sm text-ink truncate">{f.name}</p>
                  <p className="text-xs text-ink-3 mt-0.5">{f.portion}</p>
                  <p className="font-mono text-[11px] text-ink-2 mt-1 tabular-nums">
                    {Math.round(f.calories)} kcal · {Math.round(f.protein)}P · {Math.round(f.carbs)}C · {Math.round(f.fat)}F
                  </p>
                  {f.badges.length > 0 && (
                    <div className="flex flex-wrap gap-1.5 mt-2">
                      {f.badges.map((b) => (
                        <span
                          key={b}
                          className="inline-flex items-center gap-1 text-[10px] text-moss-700 bg-moss-700/10 border border-moss-700/20 px-2 py-0.5 rounded-full"
                        >
                          <IconLeaf className="w-2.5 h-2.5" />
                          {b}
                        </span>
                      ))}
                    </div>
                  )}
                  {f.flags.map((fl) => (
                    <p key={fl} className="flex items-start gap-1.5 text-[11px] text-clay-700 mt-1.5">
                      <IconAlert className="w-3 h-3 shrink-0 mt-px" />
                      {fl}
                    </p>
                  ))}
                </div>
                <span
                  className={`w-5 h-5 rounded-full border flex items-center justify-center shrink-0 mt-0.5 ${
                    included[i] ? 'bg-moss-700 border-moss-700 text-white' : 'border-black/[0.15]'
                  }`}
                >
                  {included[i] && <IconCheck className="w-3 h-3" strokeWidth={3} />}
                </span>
              </button>
            ))}
          </div>

          <MealPicker meal={meal} onChange={setMeal} />

          {error && (
            <div className="flex items-start gap-2.5 text-sm text-clay-700 bg-clay-700/10 border border-clay-700/20 rounded-2xl px-4 py-3.5 leading-relaxed">
              <IconAlert className="w-4 h-4 shrink-0 mt-0.5" />
              <span>{error}</span>
            </div>
          )}

          <button
            onClick={handleSave}
            disabled={saving || totals.n === 0}
            className="w-full bg-sky-700 hover:bg-sky-800 text-white font-semibold py-3.5 rounded-xl text-sm transition-colors disabled:opacity-60"
          >
            {saving
              ? 'Saving…'
              : `Add ${totals.n} food${totals.n !== 1 ? 's' : ''} · ${Math.round(totals.cal)} kcal to ${meal.toLowerCase()}`}
          </button>
          <button
            onClick={reset}
            className="w-full border border-black/[0.09] text-ink-2 hover:text-ink py-3.5 rounded-xl text-sm transition-colors hover:bg-paper-100"
          >
            Try a different photo
          </button>
        </div>
      )}

      {stage === 'saved' && (
        <div className="rise bg-moss-700/10 border border-moss-700/25 rounded-2xl p-5 text-center">
          <div className="mx-auto mb-3 w-10 h-10 rounded-full bg-moss-700 text-white flex items-center justify-center">
            <IconCheck className="w-5 h-5" strokeWidth={2.5} />
          </div>
          <p className="text-sm text-ink mb-4">
            Logged {savedCount} food{savedCount !== 1 ? 's' : ''} to {meal.toLowerCase()}.
          </p>
          <div className="flex gap-2">
            <button
              onClick={reset}
              className="flex-1 py-3 rounded-xl bg-sky-700 hover:bg-sky-800 text-white text-sm font-semibold transition-colors"
            >
              Analyze another
            </button>
            <Link
              href="/meal-log"
              className="flex-1 py-3 rounded-xl border border-black/[0.09] text-ink text-sm text-center hover:bg-paper-100 transition-colors"
            >
              View meals
            </Link>
          </div>
        </div>
      )}
    </div>
  )
}
