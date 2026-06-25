import { useState } from 'react'
import { Modal, Pressable, Text, View } from 'react-native'
import { BlurView } from 'expo-blur'
import * as Haptics from 'expo-haptics'
import { C, F } from '../theme'
import { AccountIcon } from './icons'

export function AccountMenu({ name, onSignOut }: { name: string | null; onSignOut: () => void }) {
  const [open, setOpen] = useState(false)
  return (
    <>
      <Pressable
        onPress={() => { Haptics.selectionAsync(); setOpen(true) }}
        style={({ pressed }) => ({
          width: 44, height: 44, borderRadius: 22, overflow: 'hidden',
          borderWidth: 1, borderColor: 'rgba(255,255,255,0.55)', opacity: pressed ? 0.85 : 1,
        })}
      >
        <BlurView intensity={28} tint="light" style={{ flex: 1, alignItems: 'center', justifyContent: 'center', backgroundColor: 'rgba(255,255,255,0.42)' }}>
          {name ? (
            <Text style={{ fontFamily: F.sansSemi, fontSize: 15, color: C.ink }}>{name[0]}</Text>
          ) : (
            <AccountIcon />
          )}
        </BlurView>
      </Pressable>

      <Modal visible={open} transparent animationType="fade" onRequestClose={() => setOpen(false)}>
        <Pressable style={{ flex: 1 }} onPress={() => setOpen(false)}>
          <View style={{ position: 'absolute', top: 96, right: 20, width: 210, backgroundColor: 'rgba(251,250,245,0.98)', borderWidth: 1, borderColor: 'rgba(0,0,0,0.07)', borderRadius: 16, padding: 14, shadowColor: '#000', shadowOpacity: 0.14, shadowRadius: 28, shadowOffset: { width: 0, height: 8 }, elevation: 8 }}>
            <Text style={{ fontFamily: F.sansMed, fontSize: 11, color: C.ink3, textTransform: 'uppercase', letterSpacing: 1.4, marginBottom: 4 }}>Signed in</Text>
            <Text style={{ fontFamily: F.sansSemi, fontSize: 15, color: C.ink, marginBottom: 12 }}>{name ?? 'Neighbor'}</Text>
            <Pressable
              onPress={() => { setOpen(false); onSignOut() }}
              style={({ pressed }) => ({ paddingVertical: 10, borderRadius: 10, borderWidth: 1, borderColor: 'rgba(0,0,0,0.07)', alignItems: 'center', opacity: pressed ? 0.7 : 1 })}
            >
              <Text style={{ fontFamily: F.sansMed, fontSize: 14, color: C.ink }}>Sign out</Text>
            </Pressable>
          </View>
        </Pressable>
      </Modal>
    </>
  )
}
