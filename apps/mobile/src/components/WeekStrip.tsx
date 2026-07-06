import { Pressable, Text, View } from 'react-native'
import * as Haptics from 'expo-haptics'
import { C, F, GRAPH, CARD_SHADOW } from '../theme'

export type WeekDay = {
  date: string      // YYYY-MM-DD
  day: number       // day-of-month
  letter: string    // S M T W T F S
  isToday: boolean
  isPast: boolean
  hasEvents: boolean
}

/** Cal-AI-style week row: floating day chips. Today is filled dark; days with
 *  events wear an amber ring; the selected day wears a green ring. */
export function WeekStrip({
  days, selected, onSelect,
}: { days: WeekDay[]; selected: string; onSelect: (date: string) => void }) {
  return (
    <View style={{ flexDirection: 'row', justifyContent: 'space-between', paddingHorizontal: 16 }}>
      {days.map((d) => {
        const isSel = d.date === selected
        const filled = d.isToday
        const ringColor = isSel ? GRAPH.green : d.hasEvents ? GRAPH.amber : 'transparent'
        return (
          <Pressable
            key={d.date}
            disabled={d.isPast}
            onPress={() => { Haptics.selectionAsync(); onSelect(d.date) }}
            style={({ pressed }) => ({
              flex: 1, alignItems: 'center', gap: 8,
              opacity: d.isPast ? 0.38 : 1,
              transform: [{ scale: pressed ? 0.94 : 1 }],
            })}
          >
            <Text style={{ fontWeight: F.sansMed, fontSize: 12, color: isSel ? C.ink : C.ink3, letterSpacing: 0.4 }}>
              {d.letter}
            </Text>
            <View style={{
              width: 42, height: 42, borderRadius: 21, alignItems: 'center', justifyContent: 'center',
              backgroundColor: filled ? C.ink : C.paper,
              borderWidth: filled ? 0 : 2.5,
              borderColor: filled ? 'transparent' : ringColor === 'transparent' ? 'rgba(0,0,0,0.05)' : ringColor,
              ...(filled ? {} : CARD_SHADOW),
            }}>
              <Text style={{ fontWeight: F.monoMed, fontSize: 15, color: filled ? C.paper : C.ink, letterSpacing: -0.2 }}>
                {d.day}
              </Text>
            </View>
            <View style={{
              width: 5, height: 5, borderRadius: 3,
              backgroundColor: d.hasEvents ? (filled ? C.moss500 : GRAPH.amber) : 'transparent',
            }} />
          </Pressable>
        )
      })}
    </View>
  )
}
