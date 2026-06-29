import { useState } from 'react'
import { Pressable, Text, View } from 'react-native'
import type { TimelineEvent } from '@hygge/core'
import { C, F } from '../theme'
import { CalendarPlusIcon, ShareIcon, PinIcon } from './icons'
import { addEventToCalendar, shareEvent, openDirections } from '../lib/eventActions'

function ActionBtn({ label, icon, active, onPress }: {
  label: string; icon: React.ReactNode; active?: boolean; onPress: () => void
}) {
  return (
    <Pressable onPress={onPress} hitSlop={6} style={({ pressed }) => ({ flexDirection: 'row', alignItems: 'center', gap: 5, opacity: pressed ? 0.6 : 1 })}>
      {icon}
      <Text style={{ fontFamily: F.sansMed, fontSize: 12.5, color: active ? C.moss700 : C.ink2 }}>{label}</Text>
    </Pressable>
  )
}

/** Quiet commitment actions beneath an event in the day sheet. */
export function EventActions({ event, date }: { event: TimelineEvent; date: string }) {
  const [added, setAdded] = useState(false)
  const input = { title: event.title, event_date: date, start_time: event.start_time, location: event.location }
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', flexWrap: 'wrap', gap: 18, paddingLeft: 64, paddingBottom: 15 }}>
      <ActionBtn
        label={added ? 'Added' : 'Add to calendar'}
        active={added}
        icon={<CalendarPlusIcon size={14} color={added ? C.moss700 : C.ink2} />}
        onPress={async () => { await addEventToCalendar(input); setAdded(true) }}
      />
      {!!event.location && (
        <ActionBtn label="Directions" icon={<PinIcon size={13} color={C.ink2} />} onPress={() => openDirections(event.location!)} />
      )}
      <ActionBtn label="Tell a neighbor" icon={<ShareIcon size={14} color={C.ink2} />} onPress={() => shareEvent(input)} />
    </View>
  )
}
