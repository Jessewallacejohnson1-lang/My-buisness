import { createClient } from './supabase/client'
import { computeTargets, type Profile, type ProfileAnswers } from './profile'

const supabase = createClient()

export async function getProfile(): Promise<Profile | null> {
  const { data, error } = await supabase.from('profiles').select('*').maybeSingle()
  if (error) throw error
  return data
}

export async function saveProfile(answers: ProfileAnswers): Promise<Profile> {
  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) throw new Error('Not signed in')
  const row = {
    user_id: user.id,
    ...answers,
    ...computeTargets(answers),
    updated_at: new Date().toISOString(),
  }
  const { data, error } = await supabase
    .from('profiles')
    .upsert(row, { onConflict: 'user_id' })
    .select()
    .single()
  if (error) throw error
  return data
}

export type FoodLog = {
  id: string
  date: string
  meal: 'Breakfast' | 'Lunch' | 'Dinner' | 'Snacks'
  food_name: string
  brand: string | null
  calories: number
  protein: number
  carbs: number
  fat: number
  fibre: number
  score: number
  badges: { label: string; icon: string; color: string }[]
  flags: string[]
  created_at: string
}

export type Exercise = { name: string; sets: number; reps: number; weight?: number }

export type Workout = {
  id: string
  date: string
  name: string
  duration_min: number
  exercises: Exercise[]
  completed: boolean
  created_at: string
}

export type WeightLog = {
  id: string
  date: string
  weight_kg: number
  created_at: string
}

/** One row per day: totals + the day's average clean score. Powers /progress. */
export type DayStat = {
  date: string
  calories: number
  protein: number
  carbs: number
  fat: number
  fibre: number
  score: number // average across the day's logs, 0 if nothing logged
  count: number
}

/** YYYY-MM-DD in the user's timezone — not UTC, so evening logs stay on today. */
export function localDate(d: Date = new Date()): string {
  return d.toLocaleDateString('en-CA')
}

export async function getFoodLogs(date: string): Promise<FoodLog[]> {
  const { data, error } = await supabase
    .from('food_logs')
    .select('*')
    .eq('date', date)
    .order('created_at', { ascending: true })
  if (error) throw error
  return data ?? []
}

export async function addFoodLog(entry: Omit<FoodLog, 'id' | 'created_at'>): Promise<FoodLog> {
  const { data, error } = await supabase
    .from('food_logs')
    .insert(entry)
    .select()
    .single()
  if (error) throw error
  return data
}

export async function deleteFoodLog(id: string): Promise<void> {
  const { error } = await supabase.from('food_logs').delete().eq('id', id)
  if (error) throw error
}

export async function getWorkouts(date: string): Promise<Workout[]> {
  const { data, error } = await supabase
    .from('workouts')
    .select('*')
    .eq('date', date)
    .order('created_at', { ascending: true })
  if (error) throw error
  return data ?? []
}

export async function addWorkout(entry: Omit<Workout, 'id' | 'created_at'>): Promise<Workout> {
  const { data, error } = await supabase
    .from('workouts')
    .insert(entry)
    .select()
    .single()
  if (error) throw error
  return data
}

export async function toggleWorkoutComplete(id: string, completed: boolean): Promise<void> {
  const { error } = await supabase.from('workouts').update({ completed }).eq('id', id)
  if (error) throw error
}

/** Persist edited sets/reps/weight for a session — used by inline strength tracking. */
export async function updateWorkoutExercises(id: string, exercises: Exercise[]): Promise<void> {
  const { error } = await supabase.from('workouts').update({ exercises }).eq('id', id)
  if (error) throw error
}

export async function deleteWorkout(id: string): Promise<void> {
  const { error } = await supabase.from('workouts').delete().eq('id', id)
  if (error) throw error
}

export async function getStreak(): Promise<number> {
  const { data, error } = await supabase
    .from('food_logs')
    .select('date')
    .order('date', { ascending: false })
    .limit(60)
  if (error || !data) return 0
  const uniqueDates = [...new Set(data.map(r => r.date))].sort().reverse()
  if (uniqueDates.length === 0) return 0
  const today = localDate()
  // If today has no log yet, still count the streak from yesterday so the
  // number doesn't drop to 0 mid-day for a user who logs later in the day.
  const offset = uniqueDates[0] === today ? 0 : 1
  let streak = 0
  for (let i = 0; i < uniqueDates.length; i++) {
    const expected = new Date()
    expected.setDate(expected.getDate() - offset - i)
    if (uniqueDates[i] === localDate(expected)) streak++
    else break
  }
  return streak
}

export async function getWeeklyCalories(): Promise<{ date: string; total: number }[]> {
  const days = Array.from({ length: 7 }, (_, i) => {
    const d = new Date()
    d.setDate(d.getDate() - (6 - i))
    return localDate(d)
  })
  const { data, error } = await supabase
    .from('food_logs')
    .select('date, calories')
    .in('date', days)
  if (error || !data) return days.map(d => ({ date: d, total: 0 }))
  return days.map(d => ({
    date: d,
    total: data.filter(r => r.date === d).reduce((s, r) => s + (r.calories ?? 0), 0),
  }))
}

/** Build the trailing list of YYYY-MM-DD dates ending today (oldest first). */
function trailingDates(days: number): string[] {
  return Array.from({ length: days }, (_, i) => {
    const d = new Date()
    d.setDate(d.getDate() - (days - 1 - i))
    return localDate(d)
  })
}

/** Per-day nutrition stats over the trailing window — one query, aggregated client-side. */
export async function getDailyStats(days: number): Promise<DayStat[]> {
  const dates = trailingDates(days)
  const empty = (date: string): DayStat => ({
    date, calories: 0, protein: 0, carbs: 0, fat: 0, fibre: 0, score: 0, count: 0,
  })
  const { data, error } = await supabase
    .from('food_logs')
    .select('date, calories, protein, carbs, fat, fibre, score')
    .gte('date', dates[0])
    .lte('date', dates[dates.length - 1])
  if (error || !data) return dates.map(empty)
  return dates.map((date) => {
    const rows = data.filter((r) => r.date === date)
    if (rows.length === 0) return empty(date)
    const sum = (k: 'calories' | 'protein' | 'carbs' | 'fat' | 'fibre') =>
      rows.reduce((s, r) => s + (r[k] ?? 0), 0)
    return {
      date,
      calories: sum('calories'),
      protein: sum('protein'),
      carbs: sum('carbs'),
      fat: sum('fat'),
      fibre: sum('fibre'),
      score: Math.round(rows.reduce((s, r) => s + (r.score ?? 0), 0) / rows.length),
      count: rows.length,
    }
  })
}

/** Completed (and pending) sessions over the trailing window, oldest first. */
export async function getWorkoutHistory(days: number): Promise<Workout[]> {
  const dates = trailingDates(days)
  const { data, error } = await supabase
    .from('workouts')
    .select('*')
    .gte('date', dates[0])
    .lte('date', dates[dates.length - 1])
    .order('date', { ascending: true })
  if (error || !data) return []
  return data
}

export async function getWeightLogs(days: number): Promise<WeightLog[]> {
  const since = trailingDates(days)[0]
  const { data, error } = await supabase
    .from('weight_logs')
    .select('*')
    .gte('date', since)
    .order('date', { ascending: true })
  if (error || !data) return []
  return data
}

export async function getLatestWeight(): Promise<WeightLog | null> {
  const { data, error } = await supabase
    .from('weight_logs')
    .select('*')
    .order('date', { ascending: false })
    .limit(1)
    .maybeSingle()
  if (error) throw error
  return data
}

/** Upsert today's (or a given day's) body weight — one entry per day. */
export async function addWeightLog(weight_kg: number, date: string = localDate()): Promise<WeightLog> {
  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) throw new Error('Not signed in')
  const { data, error } = await supabase
    .from('weight_logs')
    .upsert({ user_id: user.id, date, weight_kg }, { onConflict: 'user_id,date' })
    .select()
    .single()
  if (error) throw error
  return data
}
