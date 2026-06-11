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

export type Workout = {
  id: string
  date: string
  name: string
  duration_min: number
  exercises: { name: string; sets: number; reps: number; weight?: number }[]
  completed: boolean
  created_at: string
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

export async function deleteWorkout(id: string): Promise<void> {
  const { error } = await supabase.from('workouts').delete().eq('id', id)
  if (error) throw error
}

export async function getStreak(): Promise<number> {
  const { data, error } = await supabase
    .from('food_logs')
    .select('date')
    .order('date', { ascending: false })
  if (error || !data) return 0
  const uniqueDates = [...new Set(data.map(r => r.date))].sort().reverse()
  let streak = 0
  const today = new Date()
  for (let i = 0; i < uniqueDates.length; i++) {
    const expected = new Date(today)
    expected.setDate(today.getDate() - i)
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
