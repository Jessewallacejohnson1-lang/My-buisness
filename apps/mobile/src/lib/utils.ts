import { clsx, type ClassValue } from 'clsx'
import { twMerge } from 'tailwind-merge'

// cn() — merge conditional Tailwind/NativeWind class strings, last-wins on conflicts.
// Used by react-native-reusables components (imported as `@/lib/utils`).
export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}
