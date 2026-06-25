import { useCallback } from 'react'
import * as Haptics from 'expo-haptics'
import type { TimelineEvent } from '@hygge/core'
import { api } from './api'

/** Shared optimistic RSVP toggler over a setEvents state updater (mirrors web). */
export function useRsvp(setList: React.Dispatch<React.SetStateAction<TimelineEvent[]>>) {
  return useCallback(
    async (id: string, rsvpd: boolean) => {
      Haptics.selectionAsync()
      setList((prev) =>
        prev.map((e) => (e.id === id ? { ...e, rsvpd: !rsvpd, going_count: e.going_count + (rsvpd ? -1 : 1) } : e)),
      )
      try {
        if (rsvpd) await api.unRsvpEvent(id)
        else await api.rsvpEvent(id)
      } catch {
        setList((prev) =>
          prev.map((e) => (e.id === id ? { ...e, rsvpd, going_count: e.going_count + (rsvpd ? 1 : -1) } : e)),
        )
      }
    },
    [setList],
  )
}
