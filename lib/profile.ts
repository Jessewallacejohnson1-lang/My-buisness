export type Sex = 'male' | 'female' | 'unspecified'
export type Activity = 'sedentary' | 'light' | 'active' | 'very_active'
export type Goal = 'lose' | 'maintain' | 'build' | 'clean'
export type Pace = 'gentle' | 'moderate' | 'aggressive'
export type Diet =
  | 'none'
  | 'vegetarian'
  | 'vegan'
  | 'pescatarian'
  | 'paleo'
  | 'keto'
  | 'mediterranean'

export type ProfileAnswers = {
  sex: Sex
  age: number
  height_cm: number
  weight_kg: number
  activity: Activity
  goal: Goal
  pace: Pace
  diet: Diet
  training_days: number
  focus: string[]
}

/** Habit focus areas — shown as multi-select chips during onboarding. */
export const FOCUS_OPTIONS: { key: string; label: string }[] = [
  { key: 'protein', label: 'Eat more protein' },
  { key: 'calories', label: 'Track calories' },
  { key: 'macros', label: 'Track macros' },
  { key: 'whole_foods', label: 'Eat whole foods' },
  { key: 'vegetables', label: 'Eat more veg' },
  { key: 'fruit', label: 'Eat more fruit' },
  { key: 'fiber', label: 'Eat more fiber' },
  { key: 'less_sugar', label: 'Cut back on sugar' },
  { key: 'water', label: 'Drink more water' },
  { key: 'meal_prep', label: 'Meal prep & cook' },
  { key: 'mindful', label: 'Eat mindfully' },
  { key: 'workout', label: 'Work out more' },
  { key: 'move', label: 'Move more' },
  { key: 'sleep', label: 'Prioritize sleep' },
  { key: 'streak', label: 'Build a streak' },
]

export const FOCUS_LABELS: Record<string, string> = Object.fromEntries(
  FOCUS_OPTIONS.map((o) => [o.key, o.label])
)

/** Pre-selected, goal- and diet-aware suggestions for the focus step. */
export function recommendFocus(goal: Goal, diet: Diet): string[] {
  const byGoal: Record<Goal, string[]> = {
    lose: ['calories', 'vegetables', 'move'],
    build: ['protein', 'macros', 'workout'],
    maintain: ['streak', 'mindful', 'move'],
    clean: ['whole_foods', 'less_sugar', 'vegetables'],
  }
  const rec = [...byGoal[goal]]
  if ((diet === 'vegan' || diet === 'vegetarian') && !rec.includes('protein')) rec.push('protein')
  if (diet === 'keto' && !rec.includes('less_sugar')) rec.push('less_sugar')
  return rec.slice(0, 6)
}

export type Targets = {
  goal_calories: number
  goal_protein: number
  goal_carbs: number
  goal_fat: number
  goal_fibre: number
}

export type Profile = ProfileAnswers &
  Targets & { user_id: string; created_at: string; updated_at: string }

const ACTIVITY_FACTOR: Record<Activity, number> = {
  sedentary: 1.2,
  light: 1.375,
  active: 1.55,
  very_active: 1.725,
}

const PACE_DEFICIT: Record<Pace, number> = {
  gentle: 0.1,
  moderate: 0.18,
  aggressive: 0.25,
}

export const DIET_LABELS: Record<Diet, string> = {
  none: 'No restrictions',
  vegetarian: 'Vegetarian',
  vegan: 'Vegan',
  pescatarian: 'Pescatarian',
  paleo: 'Paleo',
  keto: 'Keto',
  mediterranean: 'Mediterranean',
}

/**
 * Daily targets from onboarding answers.
 * Energy: Mifflin-St Jeor BMR × activity, adjusted for the goal.
 * Protein: g/kg by goal (capped at 220g). Fat share shifts with diet
 * (keto high, paleo above default); carbs take the remaining calories.
 */
export function computeTargets(a: ProfileAnswers): Targets {
  const sexTerm = a.sex === 'male' ? 5 : a.sex === 'female' ? -161 : -78
  const bmr = 10 * a.weight_kg + 6.25 * a.height_cm - 5 * a.age + sexTerm
  const tdee = bmr * ACTIVITY_FACTOR[a.activity]

  let calories = tdee
  if (a.goal === 'lose') calories = tdee * (1 - PACE_DEFICIT[a.pace])
  if (a.goal === 'build') calories = tdee * 1.1
  calories = Math.max(calories, a.sex === 'male' ? 1500 : 1200)
  const goal_calories = Math.round(calories / 10) * 10

  // Focus areas nudge the macro split toward what the user cares about.
  const focus = a.focus ?? []
  let proteinPerKg = a.goal === 'build' ? 2.0 : a.goal === 'lose' ? 1.8 : 1.6
  if (focus.includes('protein')) proteinPerKg += 0.3
  const goal_protein = Math.min(240, Math.round(a.weight_kg * proteinPerKg))

  const fatShare = a.diet === 'keto' ? 0.7 : a.diet === 'paleo' ? 0.4 : 0.3
  const goal_fat = Math.round((goal_calories * fatShare) / 9)

  const carbCalories = Math.max(0, goal_calories - goal_protein * 4 - goal_fat * 9)
  const goal_carbs =
    a.diet === 'keto' ? Math.min(30, Math.round(carbCalories / 4)) : Math.round(carbCalories / 4)

  let goal_fibre = Math.round((goal_calories / 1000) * 14)
  if (focus.includes('fiber')) goal_fibre = Math.round(goal_fibre * 1.3)

  return { goal_calories, goal_protein, goal_carbs, goal_fat, goal_fibre }
}

export const KG_PER_LB = 0.45359237
export const CM_PER_IN = 2.54
