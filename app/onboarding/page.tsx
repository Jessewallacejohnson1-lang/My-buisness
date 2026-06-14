'use client'

import { useEffect, useState } from 'react'
import { useRouter } from 'next/navigation'
import { getProfile, saveProfile } from '@/lib/db'
import { haptic } from '@/lib/haptics'
import {
  computeTargets,
  recommendFocus,
  CM_PER_IN,
  KG_PER_LB,
  DIET_LABELS,
  FOCUS_OPTIONS,
  FOCUS_LABELS,
  type Activity,
  type Diet,
  type Goal,
  type Pace,
  type ProfileAnswers,
  type Sex,
} from '@/lib/profile'
import { GrowthRings } from '../components/GrowthRings'
import { IconCheck } from '../components/Icons'

const STEPS = ['Goal', 'Focus', 'About you', 'Activity', 'Diet', 'Your plan'] as const

function Chip({
  label,
  selected,
  onClick,
}: {
  label: string
  selected: boolean
  onClick: () => void
}) {
  return (
    <button
      onClick={() => { haptic('select'); onClick() }}
      aria-pressed={selected}
      className={`press rounded-full border px-4 py-2.5 text-sm transition-all ${
        selected
          ? 'border-moss-700 bg-moss-700/[0.08] text-moss-700 font-semibold'
          : 'border-black/[0.12] bg-paper-50 text-ink hover:border-black/[0.24]'
      }`}
    >
      {label}
    </button>
  )
}

function OptionCard({
  label,
  hint,
  selected,
  onClick,
}: {
  label: string
  hint?: string
  selected: boolean
  onClick: () => void
}) {
  return (
    <button
      onClick={() => { haptic('select'); onClick() }}
      className={`press w-full text-left rounded-2xl border px-4 py-3.5 transition-all ${
        selected
          ? 'border-moss-700 bg-moss-700/[0.06] shadow-[0_0_0_1px_var(--color-moss-700)]'
          : 'border-black/[0.08] bg-paper-50 hover:border-black/[0.16]'
      }`}
    >
      <span className="flex items-center justify-between gap-3">
        <span>
          <span className="block text-sm text-ink">{label}</span>
          {hint && <span className="block text-xs text-ink-3 mt-0.5">{hint}</span>}
        </span>
        <span
          className={`w-5 h-5 rounded-full border flex items-center justify-center shrink-0 ${
            selected ? 'bg-moss-700 border-moss-700 text-white' : 'border-black/[0.15]'
          }`}
        >
          {selected && <IconCheck className="pop w-3 h-3" strokeWidth={3} />}
        </span>
      </span>
    </button>
  )
}

function Field({
  label,
  children,
}: {
  label: string
  children: React.ReactNode
}) {
  return (
    <label className="block">
      <span className="block text-xs text-ink-2 mb-1.5">{label}</span>
      {children}
    </label>
  )
}

const inputCls =
  'w-full bg-paper-50 border border-black/[0.08] rounded-xl px-4 py-3 text-sm text-ink font-mono tabular-nums focus:border-moss-700/50 focus:outline-none transition-colors'

export default function OnboardingPage() {
  const router = useRouter()
  const [step, setStep] = useState(0)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const [goal, setGoal] = useState<Goal>('clean')
  const [pace, setPace] = useState<Pace>('moderate')
  const [sex, setSex] = useState<Sex>('unspecified')
  const [age, setAge] = useState(30)
  const [imperial, setImperial] = useState(true)
  const [heightCm, setHeightCm] = useState(173)
  const [weightKg, setWeightKg] = useState(75)
  const [activity, setActivity] = useState<Activity>('light')
  const [trainingDays, setTrainingDays] = useState(3)
  const [diet, setDiet] = useState<Diet>('none')
  const [focus, setFocus] = useState<string[]>([])
  const [focusTouched, setFocusTouched] = useState(false)

  // Pre-fill when editing an existing profile.
  useEffect(() => {
    getProfile()
      .then((p) => {
        if (!p) return
        setGoal(p.goal)
        setPace(p.pace)
        setSex(p.sex)
        setAge(p.age)
        setHeightCm(Number(p.height_cm))
        setWeightKg(Number(p.weight_kg))
        setActivity(p.activity)
        setTrainingDays(p.training_days)
        setDiet(p.diet)
        if (p.focus?.length) {
          setFocus(p.focus)
          setFocusTouched(true)
        }
      })
      .catch(() => {})
  }, [])

  const recommended = recommendFocus(goal, diet)
  const others = FOCUS_OPTIONS.filter((o) => !recommended.includes(o.key))

  const toggleFocus = (key: string) => {
    setFocusTouched(true)
    setFocus((cur) => (cur.includes(key) ? cur.filter((k) => k !== key) : [...cur, key]))
  }

  // Advancing past the Goal step pre-selects sensible defaults the first time.
  const next = () => {
    if (step === 0 && !focusTouched) setFocus(recommendFocus(goal, diet))
    setStep(step + 1)
  }

  const answers: ProfileAnswers = {
    sex,
    age,
    height_cm: heightCm,
    weight_kg: weightKg,
    activity,
    goal,
    pace,
    diet,
    training_days: trainingDays,
    focus,
  }
  const targets = computeTargets(answers)

  const feet = Math.floor(heightCm / CM_PER_IN / 12)
  const inches = Math.round(heightCm / CM_PER_IN - feet * 12)
  const pounds = Math.round(weightKg / KG_PER_LB)

  const finish = async () => {
    setSaving(true)
    setError(null)
    try {
      await saveProfile(answers)
      router.push('/dashboard')
    } catch (err) {
      const e = err as { code?: string; message?: string }
      setError(
        e.code === '42703' || e.code === '42P01'
          ? 'Your database is missing the latest changes. Re-run supabase/migration-profiles.sql in the Supabase SQL editor, then try again.'
          : e.message || 'Couldn’t save your plan. Check your connection and try again.'
      )
      setSaving(false)
    }
  }

  return (
    <div className="min-h-screen max-w-md mx-auto px-5 pt-8 pb-16">
      <p className="font-display text-sky-600 tracking-[0.25em] uppercase text-base mb-8">Korina</p>

      {/* progress */}
      <div className="flex gap-1.5 mb-8">
        {STEPS.map((s, i) => (
          <span
            key={s}
            className={`h-1 flex-1 rounded-full transition-colors ${
              i <= step ? 'bg-moss-700' : 'bg-paper-200'
            }`}
          />
        ))}
      </div>

      {step === 0 && (
        <section className="rise">
          <h1 className="font-display text-3xl text-ink mb-2">What brings you here?</h1>
          <p className="text-sm text-ink-2 mb-7">Your daily targets are built around this.</p>
          <div className="space-y-2">
            <OptionCard label="Lose weight" hint="A steady calorie deficit" selected={goal === 'lose'} onClick={() => setGoal('lose')} />
            <OptionCard label="Build muscle" hint="A small surplus with high protein" selected={goal === 'build'} onClick={() => setGoal('build')} />
            <OptionCard label="Maintain" hint="Hold steady, train consistently" selected={goal === 'maintain'} onClick={() => setGoal('maintain')} />
            <OptionCard label="Just eat cleaner" hint="Focus on the clean score, not calories" selected={goal === 'clean'} onClick={() => setGoal('clean')} />
          </div>
          {goal === 'lose' && (
            <div className="mt-6">
              <p className="text-xs text-ink-2 mb-2">How fast?</p>
              <div className="grid grid-cols-3 gap-1.5">
                {(
                  [
                    ['gentle', 'Gentle'],
                    ['moderate', 'Moderate'],
                    ['aggressive', 'Fast'],
                  ] as [Pace, string][]
                ).map(([p, label]) => (
                  <button
                    key={p}
                    onClick={() => { haptic('select'); setPace(p) }}
                    className={`press py-2.5 rounded-xl text-xs border transition-colors ${
                      pace === p
                        ? 'bg-moss-700 border-moss-700 text-white font-semibold'
                        : 'bg-paper-50 border-black/[0.08] text-ink-2 hover:text-ink'
                    }`}
                  >
                    {label}
                  </button>
                ))}
              </div>
            </div>
          )}
        </section>
      )}

      {step === 1 && (
        <section className="rise">
          <h1 className="font-display text-3xl text-ink mb-2">Which habits matter most?</h1>
          <p className="text-sm text-ink-2 mb-7">
            Pick as many as you like — Korina keeps them front and center.
          </p>

          <p className="text-[11px] uppercase tracking-[0.18em] text-moss-700 mb-3">
            Recommended for you
          </p>
          <div className="flex flex-wrap gap-2 mb-7">
            {recommended.map((key) => (
              <Chip
                key={key}
                label={FOCUS_LABELS[key]}
                selected={focus.includes(key)}
                onClick={() => toggleFocus(key)}
              />
            ))}
          </div>

          <p className="text-[11px] uppercase tracking-[0.18em] text-ink-2 mb-3">More habits</p>
          <div className="flex flex-wrap gap-2">
            {others.map((o) => (
              <Chip
                key={o.key}
                label={o.label}
                selected={focus.includes(o.key)}
                onClick={() => toggleFocus(o.key)}
              />
            ))}
          </div>
        </section>
      )}

      {step === 2 && (
        <section className="rise">
          <h1 className="font-display text-3xl text-ink mb-2">About you</h1>
          <p className="text-sm text-ink-2 mb-7">Used once, to estimate your energy needs.</p>

          <p className="text-xs text-ink-2 mb-2">Sex (for the calorie formula)</p>
          <div className="grid grid-cols-3 gap-1.5 mb-6">
            {(
              [
                ['female', 'Female'],
                ['male', 'Male'],
                ['unspecified', 'Skip'],
              ] as [Sex, string][]
            ).map(([s, label]) => (
              <button
                key={s}
                onClick={() => { haptic('select'); setSex(s) }}
                className={`press py-2.5 rounded-xl text-xs border transition-colors ${
                  sex === s
                    ? 'bg-moss-700 border-moss-700 text-white font-semibold'
                    : 'bg-paper-50 border-black/[0.08] text-ink-2 hover:text-ink'
                }`}
              >
                {label}
              </button>
            ))}
          </div>

          <div className="grid grid-cols-2 gap-3 mb-6">
            <Field label="Age">
              <input type="number" min={13} max={100} value={age} onChange={(e) => setAge(Math.min(100, Math.max(13, parseInt(e.target.value) || 13)))} className={inputCls} />
            </Field>
            <Field label="Units">
              <div className="grid grid-cols-2 gap-1 p-1 bg-paper-100 rounded-xl">
                {(
                  [
                    [true, 'ft · lb'],
                    [false, 'cm · kg'],
                  ] as [boolean, string][]
                ).map(([v, label]) => (
                  <button
                    key={label}
                    onClick={() => { haptic('select'); setImperial(v) }}
                    className={`press py-2 rounded-lg text-xs transition-colors ${
                      imperial === v ? 'bg-paper text-ink font-semibold shadow-sm' : 'text-ink-2'
                    }`}
                  >
                    {label}
                  </button>
                ))}
              </div>
            </Field>
          </div>

          {imperial ? (
            <div className="grid grid-cols-3 gap-3">
              <Field label="Height (ft)">
                <input type="number" min={3} max={7} value={feet} onChange={(e) => { const f = parseInt(e.target.value) || 5; setHeightCm(Math.round((f * 12 + inches) * CM_PER_IN)) }} className={inputCls} />
              </Field>
              <Field label="(in)">
                <input type="number" min={0} max={11} value={inches} onChange={(e) => { const i = Math.min(11, Math.max(0, parseInt(e.target.value) || 0)); setHeightCm(Math.round((feet * 12 + i) * CM_PER_IN)) }} className={inputCls} />
              </Field>
              <Field label="Weight (lb)">
                <input type="number" min={60} max={700} value={pounds} onChange={(e) => setWeightKg(Math.round(((parseInt(e.target.value) || 60) * KG_PER_LB) * 10) / 10)} className={inputCls} />
              </Field>
            </div>
          ) : (
            <div className="grid grid-cols-2 gap-3">
              <Field label="Height (cm)">
                <input type="number" min={100} max={230} value={heightCm} onChange={(e) => setHeightCm(Math.min(230, Math.max(100, parseInt(e.target.value) || 100)))} className={inputCls} />
              </Field>
              <Field label="Weight (kg)">
                <input type="number" min={30} max={300} value={weightKg} onChange={(e) => setWeightKg(Math.min(300, Math.max(30, parseFloat(e.target.value) || 30)))} className={inputCls} />
              </Field>
            </div>
          )}
        </section>
      )}

      {step === 3 && (
        <section className="rise">
          <h1 className="font-display text-3xl text-ink mb-2">How active are you?</h1>
          <p className="text-sm text-ink-2 mb-7">Outside of workouts — your typical day.</p>
          <div className="space-y-2 mb-7">
            <OptionCard label="Mostly sitting" hint="Desk job, light walking" selected={activity === 'sedentary'} onClick={() => setActivity('sedentary')} />
            <OptionCard label="Lightly active" hint="On your feet part of the day" selected={activity === 'light'} onClick={() => setActivity('light')} />
            <OptionCard label="Active" hint="Moving most of the day" selected={activity === 'active'} onClick={() => setActivity('active')} />
            <OptionCard label="Very active" hint="Physical work or athlete schedule" selected={activity === 'very_active'} onClick={() => setActivity('very_active')} />
          </div>
          <p className="text-xs text-ink-2 mb-2">Workouts per week</p>
          <div className="grid grid-cols-7 gap-1.5">
            {[0, 1, 2, 3, 4, 5, 6].map((d) => (
              <button
                key={d}
                onClick={() => { haptic('select'); setTrainingDays(d) }}
                className={`press py-2.5 rounded-xl text-sm font-mono tabular-nums border transition-colors ${
                  trainingDays === d
                    ? 'bg-moss-700 border-moss-700 text-white'
                    : 'bg-paper-50 border-black/[0.08] text-ink-2 hover:text-ink'
                }`}
              >
                {d}
              </button>
            ))}
          </div>
        </section>
      )}

      {step === 4 && (
        <section className="rise">
          <h1 className="font-display text-3xl text-ink mb-2">How do you eat?</h1>
          <p className="text-sm text-ink-2 mb-7">
            Shapes your macro split — and the scanner will flag foods that don&apos;t fit.
          </p>
          <div className="space-y-2">
            {(Object.entries(DIET_LABELS) as [Diet, string][]).map(([d, label]) => (
              <OptionCard
                key={d}
                label={label}
                hint={
                  d === 'keto' ? 'Very low carb, high fat' :
                  d === 'paleo' ? 'Whole foods, no grains or processed sugar' :
                  d === 'vegan' ? 'No animal products' :
                  d === 'vegetarian' ? 'No meat or fish' :
                  d === 'pescatarian' ? 'Fish, no other meat' :
                  d === 'mediterranean' ? 'Plants, olive oil, fish, whole grains' :
                  'Everything in moderation'
                }
                selected={diet === d}
                onClick={() => setDiet(d)}
              />
            ))}
          </div>
        </section>
      )}

      {step === 5 && (
        <section className="rise">
          <h1 className="font-display text-3xl text-ink mb-2">Your daily plan</h1>
          <p className="text-sm text-ink-2 mb-7">
            Tuned to your goal{diet !== 'none' ? ` and ${DIET_LABELS[diet].toLowerCase()} diet` : ''}. You can change this anytime.
          </p>

          <div className="bg-paper-50 border border-black/[0.07] rounded-3xl p-6 flex flex-col items-center mb-6">
            <GrowthRings
              size={170}
              rings={[
                { pct: 1, color: 'var(--color-honey-600)' },
                { pct: 1, color: 'var(--color-moss-700)' },
              ]}
            >
              <span className="font-mono text-3xl text-ink tabular-nums">
                {targets.goal_calories.toLocaleString()}
              </span>
              <span className="text-[10px] uppercase tracking-[0.18em] text-ink-2 mt-0.5">
                kcal / day
              </span>
            </GrowthRings>
            <div className="grid grid-cols-4 gap-2 w-full mt-5">
              {[
                ['protein', `${targets.goal_protein}g`],
                ['carbs', `${targets.goal_carbs}g`],
                ['fat', `${targets.goal_fat}g`],
                ['fibre', `${targets.goal_fibre}g`],
              ].map(([label, value]) => (
                <div key={label} className="bg-paper border border-black/[0.06] rounded-xl py-3 text-center">
                  <p className="font-mono text-sm text-ink tabular-nums">{value}</p>
                  <p className="text-[10px] text-ink-3 mt-0.5">{label}</p>
                </div>
              ))}
            </div>
          </div>

          {focus.length > 0 && (
            <div className="mb-6">
              <p className="text-[11px] uppercase tracking-[0.18em] text-ink-2 mb-3">
                You&apos;re focusing on
              </p>
              <div className="flex flex-wrap gap-2">
                {focus.map((key) => (
                  <span
                    key={key}
                    className="rounded-full border border-moss-700/25 bg-moss-700/[0.08] text-moss-700 px-3 py-1.5 text-xs"
                  >
                    {FOCUS_LABELS[key]}
                  </span>
                ))}
              </div>
            </div>
          )}

          {error && (
            <p className="text-clay-700 text-xs leading-relaxed mb-4" role="alert">
              {error}
            </p>
          )}
        </section>
      )}

      {/* nav buttons */}
      <div className="flex gap-2 mt-9">
        {step > 0 && (
          <button
            onClick={() => { haptic('tap'); setStep(step - 1) }}
            className="press flex-1 py-3.5 rounded-xl border border-black/[0.09] text-ink-2 hover:text-ink text-sm transition-colors hover:bg-paper-100"
          >
            Back
          </button>
        )}
        {step < STEPS.length - 1 ? (
          <button
            onClick={() => { haptic('tap'); next() }}
            className="press flex-[2] py-3.5 rounded-xl bg-moss-700 hover:bg-moss-800 text-white text-sm font-semibold transition-colors"
          >
            Continue
          </button>
        ) : (
          <button
            onClick={() => { haptic('success'); finish() }}
            disabled={saving}
            className="press flex-[2] py-3.5 rounded-xl bg-moss-700 hover:bg-moss-800 text-white text-sm font-semibold transition-colors disabled:opacity-60"
          >
            {saving ? 'Saving…' : 'Start tracking'}
          </button>
        )}
      </div>
    </div>
  )
}
