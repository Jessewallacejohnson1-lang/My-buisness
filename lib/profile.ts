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

  const proteinPerKg = a.goal === 'build' ? 2.0 : a.goal === 'lose' ? 1.8 : 1.6
  const goal_protein = Math.min(220, Math.round(a.weight_kg * proteinPerKg))

  const fatShare = a.diet === 'keto' ? 0.7 : a.diet === 'paleo' ? 0.4 : 0.3
  const goal_fat = Math.round((goal_calories * fatShare) / 9)

  const carbCalories = Math.max(0, goal_calories - goal_protein * 4 - goal_fat * 9)
  const goal_carbs =
    a.diet === 'keto' ? Math.min(30, Math.round(carbCalories / 4)) : Math.round(carbCalories / 4)

  const goal_fibre = Math.round((goal_calories / 1000) * 14)

  return { goal_calories, goal_protein, goal_carbs, goal_fat, goal_fibre }
}

export const KG_PER_LB = 0.45359237
export const CM_PER_IN = 2.54
