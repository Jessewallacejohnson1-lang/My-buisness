import { Pressable, Text, View } from 'react-native'
import type { TimelineEvent } from '@hygge/core'
import { C, F, HAIRLINE } from '../theme'
import { CheckIcon } from './icons'

/** Printed-paper agenda row (mirrors the web EventRow). */
export function EventRow({
  event,
  onRsvp,
  last,
}: {
  event: TimelineEvent
  onRsvp: (id: string, rsvpd: boolean) => void
  last?: boolean
}) {
  return (
    <View
      style={{
        flexDirection: 'row',
        gap: 14,
        alignItems: 'flex-start',
        paddingVertical: 15,
        borderBottomWidth: last ? 0 : 1,
        borderBottomColor: HAIRLINE,
      }}
    >
      <View style={{ width: 50, paddingTop: 2 }}>
        {!!event.start_time && (
          <Text style={{ fontFamily: F.mono, fontSize: 12, color: C.ink3, letterSpacing: 0.1 }}>{event.start_time}</Text>
        )}
      </View>

      <View style={{ flex: 1, minWidth: 0 }}>
        <Text style={{ fontFamily: F.sansSemi, fontSize: 15, color: C.ink, lineHeight: 20 }}>{event.title}</Text>
        {!!event.location && (
          <Text style={{ fontFamily: F.sans, fontSize: 13, color: C.ink2, marginTop: 2 }}>{event.location}</Text>
        )}
        <View style={{ flexDirection: 'row', alignItems: 'center', flexWrap: 'wrap', gap: 8, marginTop: 7 }}>
          {!!event.club_name && (
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 5, paddingVertical: 2, paddingHorizontal: 8, borderRadius: 11, backgroundColor: event.from_joined_club ? 'rgba(45,69,48,0.10)' : C.paper100 }}>
              {event.from_joined_club && <View style={{ width: 5, height: 5, borderRadius: 2.5, backgroundColor: C.moss700 }} />}
              <Text style={{ fontFamily: F.sansMed, fontSize: 11, color: event.from_joined_club ? C.moss700 : C.ink2 }}>{event.club_name}</Text>
            </View>
          )}
          <Text style={{ fontFamily: F.mono, fontSize: 11, color: C.ink3 }}>{event.going_count} going</Text>
        </View>
      </View>

      <Pressable
        onPress={() => onRsvp(event.id, event.rsvpd)}
        style={({ pressed }) => ({
          marginTop: 1,
          paddingHorizontal: 15,
          paddingVertical: 6,
          borderRadius: 20,
          borderWidth: 1.5,
          borderColor: event.rsvpd ? 'transparent' : 'rgba(0,0,0,0.14)',
          backgroundColor: event.rsvpd ? C.moss700 : 'transparent',
          flexDirection: 'row',
          alignItems: 'center',
          gap: 5,
          opacity: pressed ? 0.85 : 1,
        })}
      >
        <Text style={{ fontFamily: F.sansMed, fontSize: 13, color: event.rsvpd ? C.paper : C.ink2 }}>
          {event.rsvpd ? 'Going' : 'Join'}
        </Text>
        {event.rsvpd && <CheckIcon size={13} color={C.paper} />}
      </Pressable>
    </View>
  )
}
